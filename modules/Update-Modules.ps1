#Requires -Version 7.0

# AllUsers-scope modules on Linux PowerShell live under a root-owned system module path, so this
# script must be run with elevated privileges (e.g. `sudo pwsh -File Update-Modules.ps1`).
# The calling distrobox-update.sh script is responsible for invoking it that way; no internal
# sudo/re-exec logic is implemented here.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
}
catch {
    Write-Warning "Failed to set PSGallery installation policy to Trusted: $($_.Exception.Message)"
}

$failedModules = [System.Collections.Generic.List[string]]::new()

# Discovered rather than hardcoded: this covers whatever has actually been installed via
# Install-Module in this container (today's Install-Modules.ps1 list and anything added since),
# without maintaining a second module list that could drift out of sync with that file.
try {
    $installedModules = Get-InstalledModule -ErrorAction Stop
}
catch {
    Write-Warning "Failed to enumerate installed modules via Get-InstalledModule: $($_.Exception.Message)"
    $installedModules = @()
}

if (-not $installedModules) {
    Write-Host 'No installed modules found to update.' -ForegroundColor Cyan
}

foreach ($module in $installedModules) {
    $moduleName = $module.Name

    Write-Host "Updating module '$moduleName'..." -ForegroundColor Cyan

    try {
        Update-Module -Name $moduleName -Force -ErrorAction Stop
        Write-Host "Updated module '$moduleName'." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to update module '$moduleName': $($_.Exception.Message)"
        $failedModules.Add($moduleName)
    }
}

# This script never touches $PROFILE.AllUsersAllHosts: the auto-import profile lines are owned
# and managed by Install-Modules.ps1, and updating an already-installed module does not change
# whether it should be auto-imported.

if ($failedModules.Count -gt 0) {
    Write-Warning "The following module(s) failed to update: $($failedModules -join ', ')"
    exit 1
}

exit 0
