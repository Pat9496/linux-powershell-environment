#!/usr/bin/env bash
set -euo pipefail

# Design choice: nothing installed inside the PWSHenv container is ever
# exported to the host (no `distrobox-export`, no host-side .desktop entries
# or wrapper binaries). The only host-side artifact this script creates is
# the container itself; PowerShell and its modules stay inside it and are
# reached with `distrobox enter`.

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
  local name="$1"
  printf 'Installing PowerShell 7 and its modules inside "%s"...\n' "${name}"
  distrobox enter --name "${name}" -- bash "${BOOTSTRAP_SCRIPT}"
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
  printf 'Usage: %s [--reset-config | --clean-reinstall] [-h|--help]\n' "$(basename -- "$0")"
  printf '\n'
  printf '  (no flags)         Create (or recreate) the %s Distrobox container and\n' "${CONTAINER_NAME}"
  printf '                     install PowerShell 7 and its modules inside it.\n'
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
  printf '  -h, --help         Show this help message and exit.\n'
}

main() {
  local do_reset_config=0 do_clean_reinstall=0

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

  check_host_prerequisites

  if (( do_reset_config )); then
    reset_pwshenv_config "${CONTAINER_NAME}"
    exit 0
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

  run_bootstrap_in_container "${CONTAINER_NAME}"

  printf '\nPWSHenv container "%s" is ready. Enter it with: distrobox enter %s\n' "${CONTAINER_NAME}" "${CONTAINER_NAME}"
}

main "$@"
