#!/usr/bin/env bash
set -euo pipefail

# This script is invoked by install.sh via `distrobox enter -- bash
# distrobox-update.sh` (the --update flag) and is not meant to be run
# standalone on the host.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
readonly SCRIPT_DIR
readonly MODULE_UPDATER="${SCRIPT_DIR}/modules/Update-Modules.ps1"

update_apt_packages() {
  printf 'Updating apt package lists and upgrading installed packages (including the powershell package from Microsoft'"'"'s repo)...\n'
  if ! sudo apt-get update; then
    printf 'Warning: apt-get update failed; continuing with upgrade using the existing package lists.\n' >&2
  fi
  if ! sudo apt-get upgrade -y; then
    printf 'Warning: apt-get upgrade failed; some packages (including possibly powershell) may not have been updated.\n' >&2
  fi
}

run_module_updater() {
  printf 'Running module updater: %s\n' "${MODULE_UPDATER}"
  if ! sudo pwsh -NoLogo -NoProfile -NonInteractive -File "${MODULE_UPDATER}"; then
    printf 'Warning: module updater exited with a non-zero status; some PowerShell modules may not have been updated.\n' >&2
  fi
}

main() {
  if ! command -v sudo >/dev/null 2>&1; then
    printf 'Error: sudo not found inside the container; cannot update packages.\n' >&2
    exit 1
  fi

  update_apt_packages

  run_module_updater

  printf 'PWSHenv container update complete.\n'
}

main "$@"
