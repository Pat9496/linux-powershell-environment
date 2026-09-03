#!/usr/bin/env bash
set -euo pipefail

# This script is invoked by install.sh via `distrobox enter -- bash
# distrobox-bootstrap.sh` and is not meant to be run standalone on the host.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
readonly SCRIPT_DIR
readonly MODULE_INSTALLER="${SCRIPT_DIR}/modules/Install-Modules.ps1"

# The PWSHenv base image is fixed to ubuntu:24.04 (see install.sh), so this
# script calls apt-get directly instead of doing DEVenv-style multi-package-
# manager detection.
readonly BASELINE_PACKAGES=(
  curl
  ca-certificates
  gnupg
  git
  jq
  unzip
  krb5-user
)

install_powershell() {
  sudo apt-get update || return 1
  sudo apt-get install -y wget apt-transport-https software-properties-common || return 1
  wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" || return 1
  sudo dpkg -i packages-microsoft-prod.deb || return 1
  rm packages-microsoft-prod.deb
  sudo apt-get update || return 1
  sudo apt-get install -y powershell || return 1
}

install_baseline_packages() {
  local -a failed_packages=()
  local pkg
  for pkg in "${BASELINE_PACKAGES[@]}"; do
    printf 'Installing %s...\n' "${pkg}"
    if ! sudo apt-get install -y "${pkg}"; then
      failed_packages+=("${pkg}")
      printf 'Warning: failed to install %s, continuing.\n' "${pkg}" >&2
    fi
  done
  if (( ${#failed_packages[@]} > 0 )); then
    printf 'Warning: the following baseline packages could not be installed: %s\n' "${failed_packages[*]}" >&2
  fi
}

export_powershell_app() {
  local desktop_dir="${HOME}/.local/share/applications"
  local desktop_file="${desktop_dir}/powershell.desktop"

  if ! mkdir -p -- "${desktop_dir}"; then
    printf 'Warning: failed to create %s; skipping desktop application menu integration.\n' "${desktop_dir}" >&2
    return 0
  fi

  if ! cat > "${desktop_file}" <<'EOF'
[Desktop Entry]
Type=Application
Name=PowerShell
Comment=PowerShell 7 (PWSHenv)
Exec=pwsh
Icon=utilities-terminal
Terminal=true
Categories=Development;ConsoleOnly;
EOF
  then
    printf 'Warning: failed to write %s; skipping desktop application menu integration.\n' "${desktop_file}" >&2
    return 0
  fi

  if ! command -v distrobox-export >/dev/null 2>&1; then
    printf 'Warning: distrobox-export not found inside the container; skipping desktop application menu integration.\n' >&2
    return 0
  fi

  if ! distrobox-export --app "${desktop_file}"; then
    printf 'Warning: distrobox-export failed; PowerShell will not appear in the host application menu.\n' >&2
    return 0
  fi

  printf 'Exported PowerShell to the host application menu via distrobox-export.\n'
}

run_module_installer() {
  local starship_decision="$1"
  printf 'Running module installer: %s\n' "${MODULE_INSTALLER}"
  if ! sudo pwsh -NoLogo -NoProfile -NonInteractive -File "${MODULE_INSTALLER}" -EnableStarship "${starship_decision}"; then
    printf 'Warning: module installer exited with a non-zero status; PowerShell itself is installed but some modules may be missing.\n' >&2
  fi
}

main() {
  local starship_decision="${1:-false}"

  if ! command -v sudo >/dev/null 2>&1; then
    printf 'Error: sudo not found inside the container; cannot install packages.\n' >&2
    exit 1
  fi

  printf 'Installing PowerShell 7 (Microsoft apt repository for Ubuntu)...\n'
  if ! install_powershell; then
    printf 'Error: PowerShell installation failed; nothing downstream can work without it.\n' >&2
    exit 1
  fi

  if ! command -v pwsh >/dev/null 2>&1; then
    printf 'Error: pwsh not found on PATH after installation.\n' >&2
    exit 1
  fi

  export_powershell_app

  install_baseline_packages

  run_module_installer "${starship_decision}"

  printf 'PWSHenv container bootstrap complete. PowerShell 7 is installed.\n'
}

main "$@"
