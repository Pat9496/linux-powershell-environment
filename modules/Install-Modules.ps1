#Requires -Version 7.0

# AllUsers scope on Linux PowerShell installs into a root-owned system module path, so this
# script must be run with elevated privileges (e.g. `sudo pwsh -File Install-Modules.ps1`).
# The calling bootstrap script is responsible for invoking it that way; no internal
# sudo/re-exec logic is implemented here.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction Stop
}
catch {
    Write-Warning "Failed to set PSGallery installation policy to Trusted: $($_.Exception.Message)"
}

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.DirectoryManagement',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Teams',
    'Microsoft.Graph.Sites',
    'Microsoft.Graph.Mail',
    'ExchangeOnlineManagement',
    'MicrosoftTeams',
    'Az',
    'PnP.PowerShell'
)

$failedModules = [System.Collections.Generic.List[string]]::new()

function Add-ModuleToAllUsersProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ModuleName
    )

    $profilePath = $PROFILE.AllUsersAllHosts

    if (-not (Test-Path -Path $profilePath)) {
        $profileDirectory = Split-Path -Path $profilePath -Parent

        if (-not (Test-Path -Path $profileDirectory)) {
            New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        }

        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }

    $pattern = "^Import-Module\s+$([regex]::Escape($ModuleName))\b"
    $alreadyPresent = Select-String -Path $profilePath -Pattern $pattern -Quiet

    if (-not $alreadyPresent) {
        Add-Content -Path $profilePath -Value "Import-Module $ModuleName"
    }
}

foreach ($moduleName in $requiredModules) {
    $installedModule = Get-Module -ListAvailable -Name $moduleName

    if ($installedModule) {
        Write-Host "Module '$moduleName' is already installed; skipping installation." -ForegroundColor Green
    }
    else {
        Write-Host "Installing module '$moduleName' for all users..." -ForegroundColor Cyan

        try {
            Install-Module -Name $moduleName -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
            Write-Host "Installed module '$moduleName'." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to install module '$moduleName': $($_.Exception.Message)"
            $failedModules.Add($moduleName)
            continue
        }
    }

    try {
        Import-Module -Name $moduleName -Global -Force -ErrorAction Stop
        Write-Host "Imported module '$moduleName' into the current session." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to import module '$moduleName': $($_.Exception.Message)"
        $failedModules.Add($moduleName)
        continue
    }

    try {
        Add-ModuleToAllUsersProfile -ModuleName $moduleName
        Write-Host "Activated module '$moduleName' for all future sessions (added to the all-users profile)." -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to add module '$moduleName' to the all-users profile ('$($PROFILE.AllUsersAllHosts)'): $($_.Exception.Message)"
    }
}

Write-Warning "Skipping the 'ActiveDirectory' module: it is a Windows-only RSAT binary module that depends on Active Directory Web Services (ADWS) and cannot run on Linux/PowerShell 7. There is no cross-platform equivalent to install. To manage on-premises Active Directory from this container, use PowerShell remoting (New-PSSession / Invoke-Command) to a domain-joined Windows host that has RSAT installed."

if ($failedModules.Count -gt 0) {
    Write-Warning "The following module(s) failed to install or activate: $($failedModules -join ', ')"
    exit 1
}

exit 0
