#!/usr/bin/env bash
set -euo pipefail

# Design choice: nothing installed inside the PWSHenv container is ever
# exported to the host (no `distrobox-export`, no host-side .desktop entries
# for arbitrary container packages). The only host-side artifact this script
# creates is the container itself, plus one thin wrapper script (`powershell`)
# that simply shells out to `distrobox enter` at run time.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
readonly SCRIPT_DIR
readonly BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/distrobox-bootstrap.sh"

readonly CONTAINER_NAME="PWSHenv"
# Ubuntu is the distro Microsoft publishes PowerShell packages for fastest via
# its official apt repo, and 24.04 is the current Ubuntu LTS. Because the base
# image is fixed to this one known distro, distrobox-bootstrap.sh calls
# apt-get directly instead of doing DEVenv-style multi-package-manager
# detection.
readonly BASE_IMAGE="ubuntu:24.04"
readonly DEFAULT_PWSHENV_HOME="${HOME}/PWSHenv-home"
readonly HOST_BIN_DIR="${HOME}/.local/bin"
readonly HOST_WRAPPER_NAME="powershell"
# Literal ${HOME} is intentional: this line is written into the user's shell
# rc file for that shell to expand at its own startup, not for this script to
# expand now.
# shellcheck disable=SC2016
readonly HOST_BIN_PATH_EXPORT_LINE='export PATH="${HOME}/.local/bin:$PATH"'

# PowerShell's standard XDG Base Directory locations on Linux: config,
# cache, and data/modules respectively. Nothing else under a home directory
# is ever touched by the purge/reset helpers below.
readonly -a PWSH_STATE_DIRS=(
  ".config/powershell"
  ".cache/powershell"
  ".local/share/powershell"
)

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found on host. Install it before running this script."
}

check_host_prerequisites() {
  require_cmd distrobox
  if ! command -v podman >/dev/null 2>&1 && ! command -v docker >/dev/null 2>&1; then
    die "neither podman nor docker found on host. Distrobox needs one of them."
  fi
  [[ -f "${BOOTSTRAP_SCRIPT}" ]] || die "bootstrap script not found at ${BOOTSTRAP_SCRIPT}"
}

container_exists() {
  local name="$1"
  distrobox list --no-color 2>/dev/null | awk -F'|' -v name="${name}" '
    NR > 1 {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      if ($2 == name) { found = 1 }
    }
    END { exit !found }
  '
}

prompt_yes_no() {
  local prompt="$1" default="$2" reply suffix
  suffix="y/N"
  [[ "${default}" == "y" ]] && suffix="Y/n"
  while true; do
    read -r -p "${prompt} [${suffix}]: " reply
    reply="${reply:-${default}}"
    case "${reply,,}" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) printf 'Please answer y or n.\n' >&2 ;;
    esac
  done
}

prompt_home_mode() {
  local name="$1" choice
  printf 'Choose the home directory for the "%s" container:\n' "${name}" >&2
  printf '  1) Use the existing user home\n' >&2
  printf '  2) Create a new, separate PWSHenv home\n' >&2
  while true; do
    read -r -p "Selection [1]: " choice
    choice="${choice:-1}"
    case "${choice}" in
      1) printf 'existing\n'; return 0 ;;
      2) printf 'separate\n'; return 0 ;;
      *) printf 'Please enter 1 or 2.\n' >&2 ;;
    esac
  done
}

prompt_pwshenv_home_path() {
  local path
  read -r -p "Path for the new PWSHenv home [${DEFAULT_PWSHENV_HOME}]: " path
  path="${path:-${DEFAULT_PWSHENV_HOME}}"
  path="${path/#\~/${HOME}}"
  if [[ -z "${path}" || "${path}" == "/" || "${path}" == "${HOME}" ]]; then
    die "refusing to use '${path}' as the PWSHenv home; choose a dedicated path that is not '/' or your real home."
  fi
  printf '%s\n' "${path}"
}

create_container() {
  local name="$1" image="$2" home_mode="$3" pwshenv_home="$4"
  local -a create_args=(--name "${name}" --image "${image}" --yes)
  if [[ "${home_mode}" == "separate" ]]; then
    create_args+=(--home "${pwshenv_home}")
  fi
  printf 'Creating distrobox container "%s" from image "%s"...\n' "${name}" "${image}"
  distrobox create "${create_args[@]}"
}

run_bootstrap_in_container() {
  local name="$1" starship_decision="$2"
  printf 'Installing PowerShell 7 and its modules inside "%s"...\n' "${name}"
  distrobox enter --name "${name}" -- bash "${BOOTSTRAP_SCRIPT}" "${starship_decision}"
}

install_host_wrapper() {
  local wrapper_path="${HOST_BIN_DIR}/${HOST_WRAPPER_NAME}" tmp_path=""
  mkdir -p -- "${HOST_BIN_DIR}"

  trap '[[ -n "${tmp_path}" ]] && rm -f -- "${tmp_path}"' EXIT

  tmp_path="$(mktemp -- "${HOST_BIN_DIR}/.${HOST_WRAPPER_NAME}.XXXXXX")"
  cat > "${tmp_path}" <<WRAPPER_EOF
#!/usr/bin/env bash
# Distrobox shares the host filesystem so deeply that generic container
# markers like /run/.containerenv and /.dockerenv don't reliably show up
# inside it; distrobox's own docs recommend checking \$CONTAINER_ID instead.
# Compare against this wrapper's own container name, since \$CONTAINER_ID is
# also set (to some other container's name) when running inside a different
# distrobox container that happens to share this same ~/.local/bin wrapper.
if [[ "\${CONTAINER_ID:-}" == "${CONTAINER_NAME}" ]]; then
  IFS=':' read -r -a path_parts <<< "\${PATH}"
  filtered_path=""
  for path_part in "\${path_parts[@]}"; do
    if [[ "\${path_part}" != "${HOST_BIN_DIR}" ]]; then
      filtered_path="\${filtered_path:+\${filtered_path}:}\${path_part}"
    fi
  done
  PATH="\${filtered_path}" exec pwsh "\$@"
else
  exec distrobox enter "${CONTAINER_NAME}" -- pwsh "\$@"
fi
WRAPPER_EOF
  chmod +x -- "${tmp_path}"
  mv -f -- "${tmp_path}" "${wrapper_path}"
  tmp_path=""
  printf 'Installed host wrapper: %s\n' "${wrapper_path}"

  trap - EXIT
}

resolve_shell_rc_file() {
  if [[ "$(basename -- "${SHELL:-}")" == "zsh" ]]; then
    printf '%s\n' "${HOME}/.zshrc"
  else
    printf '%s\n' "${HOME}/.bashrc"
  fi
}

chezmoi_available_and_initialized() {
  command -v chezmoi >/dev/null 2>&1 || return 1
  chezmoi source-path >/dev/null 2>&1
}

# Appends the PATH export using a literal ${HOME}/$PATH so the rc file's own
# shell expands them at startup, not this script (same literal-vs-expanded
# care as the plain-reminder message printed below when chezmoi is unusable).
# Idempotency is checked against the ${HOME}-relative suffix of HOST_BIN_DIR
# (".local/bin") rather than HOST_BIN_DIR's own already-expanded value, since
# the appended line never contains that expanded value literally.
add_host_bin_to_path_via_chezmoi() {
  local rc_file home_suffix add_cmd
  rc_file="$(resolve_shell_rc_file)"
  home_suffix="${HOST_BIN_DIR#"${HOME}"}"

  if ! grep -qF -- "${home_suffix}" "${rc_file}" 2>/dev/null; then
    printf '%s\n' "${HOST_BIN_PATH_EXPORT_LINE}" >> "${rc_file}"
  fi

  add_cmd="add"
  chezmoi source-path "${rc_file}" >/dev/null 2>&1 && add_cmd="re-add"

  if chezmoi "${add_cmd}" "${rc_file}"; then
    printf 'Added %s to PATH in %s and captured the change with chezmoi %s.\n' "${HOST_BIN_DIR}" "${rc_file}" "${add_cmd}"
  else
    printf 'Warning: updated %s but chezmoi %s %s failed; run it manually to capture the change in chezmoi.\n' "${rc_file}" "${add_cmd}" "${rc_file}" >&2
  fi
}

# Removes exactly the line add_host_bin_to_path_via_chezmoi appends, so that
# function can cleanly re-append it afterwards. A no-op (returns immediately)
# when the line isn't present, so repeated calls stay idempotent. Preserves
# the rc file's original permission bits across the rewrite, since mktemp
# creates its temp file with restrictive default permissions.
strip_host_bin_path_line() {
  local rc_file="$1" tmp_file orig_mode
  grep -qxF -- "${HOST_BIN_PATH_EXPORT_LINE}" "${rc_file}" 2>/dev/null || return 0
  orig_mode="$(stat -c '%a' "${rc_file}")"
  tmp_file="$(mktemp -- "${rc_file}.XXXXXX")"
  grep -vxF -- "${HOST_BIN_PATH_EXPORT_LINE}" "${rc_file}" > "${tmp_file}" || true
  chmod "${orig_mode}" "${tmp_file}"
  mv -f -- "${tmp_file}" "${rc_file}"
}

# Explicit force-refresh path for --reset-config: only runs when chezmoi is
# available/initialized AND the resolved rc file is already chezmoi-managed,
# so a plain --reset-config run on a host without chezmoi (or with an
# unmanaged rc file) behaves exactly as before, with no new messages.
refresh_chezmoi_path_line_if_managed() {
  local rc_file
  chezmoi_available_and_initialized || return 0
  rc_file="$(resolve_shell_rc_file)"
  chezmoi source-path "${rc_file}" >/dev/null 2>&1 || return 0
  strip_host_bin_path_line "${rc_file}"
  add_host_bin_to_path_via_chezmoi
}

check_host_bin_on_path() {
  case ":${PATH}:" in
    *":${HOST_BIN_DIR}:"*) ;;
    *)
      printf '\nNote: %s is not on your PATH.\n' "${HOST_BIN_DIR}" >&2
      if chezmoi_available_and_initialized; then
        add_host_bin_to_path_via_chezmoi
      else
        # $PATH here is literal text for the user's ~/.bashrc, not meant to expand in this script.
        # shellcheck disable=SC2016
        printf 'Add it to your shell startup file (e.g. export PATH="%s:$PATH" in ~/.bashrc) so the %s command is found.\n' "${HOST_BIN_DIR}" "${HOST_WRAPPER_NAME}" >&2
      fi
      ;;
  esac
}

# The rm command runs via `bash -c` inside the container so that $HOME is
# expanded by the container's own shell rather than the host's; a bare `~`
# on this line would be expanded by the host shell before distrobox ever
# runs, which resolves to the wrong home when a separate PWSHenv home was
# chosen at container creation.
reset_pwshenv_config() {
  local name="$1"
  container_exists "${name}" || die "container \"${name}\" does not exist. Run install.sh without any flags first to create it."
  if ! prompt_yes_no "This deletes the PowerShell profile, module state, and history inside container \"${name}\" (~/.config/powershell, ~/.cache/powershell, and ~/.local/share/powershell) and cannot be undone. Continue?" "n"; then
    printf 'Aborted; PowerShell configuration was not reset.\n'
    return 0
  fi
  printf 'Resetting PowerShell configuration inside container "%s"...\n' "${name}"
  # SC2016: $HOME here is meant to be expanded by the container's bash -c
  # shell, not this host script, so the single quotes are deliberate.
  # shellcheck disable=SC2016
  distrobox enter "${name}" -- bash -c 'rm -rf -- "${HOME}/.config/powershell" "${HOME}/.cache/powershell" "${HOME}/.local/share/powershell"'
  printf 'PowerShell configuration inside container "%s" has been reset to defaults.\n' "${name}"
  refresh_chezmoi_path_line_if_managed
}

# Purges PowerShell's state directories directly on the host filesystem
# (not via `distrobox enter`), because this runs before the container
# exists: the caller has already resolved which host directory will be
# bind-mounted as the container's home (either the real host $HOME, or a
# separate PWSHenv home directory).
purge_powershell_state_dirs() {
  local home_path="$1" reldir target
  if [[ -z "${home_path}" || "${home_path}" == "/" ]]; then
    die "refusing to purge PowerShell state dirs: resolved home path is empty or '/'."
  fi
  for reldir in "${PWSH_STATE_DIRS[@]}"; do
    target="${home_path}/${reldir}"
    if [[ -e "${target}" ]]; then
      printf 'Removing %s...\n' "${target}"
      rm -rf -- "${target}"
    else
      printf '%s not present; skipping.\n' "${target}"
    fi
  done
}

usage() {
  printf 'Usage: %s [--reset-config | --clean-reinstall] [--use-starship | --no-starship] [-h|--help]\n' "$(basename -- "$0")"
  printf '\n'
  printf '  (no flags)         Create (or recreate) the %s Distrobox container and\n' "${CONTAINER_NAME}"
  printf '                     install PowerShell 7 and its modules inside it. Also\n'
  printf '                     installs a "%s" host command to enter it directly.\n' "${HOST_WRAPPER_NAME}"
  printf '  --reset-config     Reset PowerShell'"'"'s user configuration inside the\n'
  printf '                     existing %s container (profile, module state,\n' "${CONTAINER_NAME}"
  printf '                     history) without recreating the container. Requires\n'
  printf '                     the container to already exist.\n'
  printf '  --clean-reinstall  Like the default run, but also purges PowerShell'"'"'s\n'
  printf '                     state directories (~/.config/powershell,\n'
  printf '                     ~/.cache/powershell, ~/.local/share/powershell) under\n'
  printf '                     the resolved home directory before recreating the\n'
  printf '                     %s container, so the reinstall behaves as if\n' "${CONTAINER_NAME}"
  printf '                     PowerShell was never installed. Cannot be combined\n'
  printf '                     with --reset-config.\n'
  printf '  --use-starship     Force-enable Starship PowerShell prompt integration.\n'
  printf '                     Only takes effect on a plain run or --clean-reinstall\n'
  printf '                     (the module installer never runs under --reset-config).\n'
  printf '                     Cannot be combined with --no-starship.\n'
  printf '  --no-starship      Force-disable Starship PowerShell prompt integration.\n'
  printf '                     Same restrictions as --use-starship. With neither flag\n'
  printf '                     given, this is auto-detected from whether "starship" is\n'
  printf '                     found on the host'"'"'s PATH.\n'
  printf '  -h, --help         Show this help message and exit.\n'
}

main() {
  local do_reset_config=0 do_clean_reinstall=0 do_use_starship=0 do_no_starship=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reset-config)
        do_reset_config=1
        shift
        ;;
      --clean-reinstall)
        do_clean_reinstall=1
        shift
        ;;
      --use-starship)
        do_use_starship=1
        shift
        ;;
      --no-starship)
        do_no_starship=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
  done

  if (( do_reset_config && do_clean_reinstall )); then
    die "--clean-reinstall and --reset-config cannot be combined"
  fi

  if (( do_use_starship && do_no_starship )); then
    die "--use-starship and --no-starship cannot be combined"
  fi

  if (( do_reset_config && ( do_use_starship || do_no_starship ) )); then
    die "--use-starship/--no-starship have no effect with --reset-config, since it never re-runs the module installer"
  fi

  check_host_prerequisites

  if (( do_reset_config )); then
    reset_pwshenv_config "${CONTAINER_NAME}"
    exit 0
  fi

  local starship_decision
  if (( do_use_starship )); then
    starship_decision="true"
  elif (( do_no_starship )); then
    starship_decision="false"
  elif command -v starship >/dev/null 2>&1; then
    starship_decision="true"
  else
    starship_decision="false"
  fi

  local home_mode pwshenv_home=""
  home_mode="$(prompt_home_mode "${CONTAINER_NAME}")"

  if [[ "${home_mode}" == "separate" ]]; then
    pwshenv_home="$(prompt_pwshenv_home_path)"
    mkdir -p -- "${pwshenv_home}"
  fi

  if (( do_clean_reinstall )); then
    local resolved_home
    resolved_home="${pwshenv_home:-${HOME}}"
    if [[ -z "${resolved_home}" || "${resolved_home}" == "/" ]]; then
      die "refusing to clean-reinstall: resolved home path is empty or '/'."
    fi
    if ! prompt_yes_no "This will destroy and recreate the \"${CONTAINER_NAME}\" container, AND permanently delete .config/powershell, .cache/powershell, and .local/share/powershell under \"${resolved_home}\". Continue?" "n"; then
      printf 'Aborted; clean reinstall was not performed.\n'
      exit 0
    fi
    purge_powershell_state_dirs "${resolved_home}"
  fi

  # Always recreate rather than reuse: a reused container can silently carry
  # over a half-applied prior install or drifted packages, so install.sh
  # treats every run as a from-scratch (re-)install instead of an incremental
  # update.
  if container_exists "${CONTAINER_NAME}"; then
    printf 'Warning: container "%s" already exists; it and everything inside it will be destroyed and recreated from scratch.\n' "${CONTAINER_NAME}" >&2
    distrobox rm -f "${CONTAINER_NAME}"
  fi

  create_container "${CONTAINER_NAME}" "${BASE_IMAGE}" "${home_mode}" "${pwshenv_home}"

  run_bootstrap_in_container "${CONTAINER_NAME}" "${starship_decision}"

  install_host_wrapper
  check_host_bin_on_path

  printf '\nPWSHenv container "%s" is ready. Enter it with: distrobox enter %s\n' "${CONTAINER_NAME}" "${CONTAINER_NAME}"
  printf 'PowerShell is also available directly from the host terminal via the %s command.\n' "${HOST_WRAPPER_NAME}"
}

main "$@"
