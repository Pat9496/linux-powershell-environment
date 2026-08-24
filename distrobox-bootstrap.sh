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

run_module_installer() {
  printf 'Running module installer: %s\n' "${MODULE_INSTALLER}"
  if ! sudo pwsh -NoLogo -NoProfile -NonInteractive -File "${MODULE_INSTALLER}"; then
    printf 'Warning: module installer exited with a non-zero status; PowerShell itself is installed but some modules may be missing.\n' >&2
  fi
}

main() {
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

  install_baseline_packages

  run_module_installer

  printf 'PWSHenv container bootstrap complete. PowerShell 7 is installed.\n'
}

main "$@"
