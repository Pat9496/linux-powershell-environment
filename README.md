[![Shell: Bash](https://img.shields.io/badge/shell-bash-blue)](https://www.gnu.org/software/bash/)
[![PowerShell: 7](https://img.shields.io/badge/powershell-7-blue)](https://github.com/PowerShell/PowerShell)

[Deutsche Version](README.de.md)

## Table of Contents

- [About](#about)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
  - [Running the Installation Script](#running-the-installation-script)
  - [Installation Prompts](#installation-prompts)
  - [Entering the Container](#entering-the-container)
- [Resetting PowerShell Configuration](#resetting-powershell-configuration)
- [Clean Reinstall](#clean-reinstall)
- [What Gets Installed](#what-gets-installed)
- [Home Directory Options](#home-directory-options)
  - [Using Your Existing Home](#using-your-existing-home)
  - [Creating a Separate PWSHenv Home](#creating-a-separate-pwshenv-home)
- [Contributing](#contributing)
- [Credits](#credits)

## About

PWSHenv is an automated setup script for a Distrobox-based PowerShell 7 environment tailored for Microsoft-cloud administration. It configures a container with PowerShell 7 and the modules needed to manage Entra ID, Microsoft 365, and tenant resources. For on-premises Active Directory, the container supports PowerShell remoting to a domain-joined Windows host. Run the installation script on the host, and it creates and provisions a container with all necessary tools.

## Requirements

On the host system, you must have:

- A Linux system (any distribution)
- `distrobox` installed
- Either `podman` or `docker` available as the container runtime

The installation script itself is self-contained and will set up everything else inside the container.

## Getting Started

### Running the Installation Script

Clone this repository on the host system, then run the installation script:

```bash
git clone <repository-url>
cd PWSHenv
./install.sh
```

The script will check for `distrobox` and `podman`/`docker` on the host, then guide you through the setup process. The container is always created with the fixed name `PWSHenv` using the `ubuntu:24.04` image.

**Why Ubuntu 24.04?** Microsoft publishes PowerShell packages for Ubuntu fastest via its official apt repository. The 24.04 release is the current Ubuntu LTS, ensuring long-term package stability and support.

### Installation Prompts

During installation, you will be prompted for the following:

1. **Home directory mode** — Choose between using your existing user home or creating a separate PWSHenv home (see [Home Directory Options](#home-directory-options) below).

**Container Recreation:** The script always destroys and recreates the container from scratch on every run. This is intentional — it prevents silently carrying over a half-applied prior installation or drifted packages. If a container named `PWSHenv` already exists, the script will warn you and remove it before creating a new one.

### Entering the Container

After installation completes, enter the container with:

```bash
distrobox enter PWSHenv
```

## Resetting PowerShell Configuration

To reset PowerShell's user configuration inside the container without recreating the entire container, use the `--reset-config` flag:

```bash
./install.sh --reset-config
```

This flag requires the `PWSHenv` container to already exist. The script will prompt for confirmation, then remove `~/.config/powershell`, `~/.cache/powershell`, and `~/.local/share/powershell` inside the container (erasing the profile, module state, and history) without touching or rebuilding anything else.

To view the help message and see all available flags, run:

```bash
./install.sh -h
```

or

```bash
./install.sh --help
```

## Clean Reinstall

To destroy and recreate the container while also purging PowerShell's state directories, use the `--clean-reinstall` flag:

```bash
./install.sh --clean-reinstall
```

This performs the same overall flow as a standard `./install.sh` run (host prerequisite checks, home-directory-mode prompt, container creation, and bootstrap), but first purges PowerShell's state directories (`~/.config/powershell`, `~/.cache/powershell`, and `~/.local/share/powershell`) under the resolved home path—the real host home in "existing home" mode, or the separate PWSHenv home in "separate home" mode. This gives a completely clean slate as if PowerShell was never installed.

The script will prompt for explicit confirmation before performing any destructive action, clearly stating that the container will be destroyed and recreated and that the three state directories will be permanently deleted. If you decline, the script exits without touching the container or any files.

Unlike `--reset-config`, which clears PowerShell state on an existing container without rebuilding it, `--clean-reinstall` destroys and recreates the container too, for a fully clean slate.

The `--clean-reinstall` and `--reset-config` flags are mutually exclusive—passing both is an error.

## What Gets Installed

The bootstrap script inside the container installs the following:

- **PowerShell 7** — Installed via Microsoft's official apt repository for Ubuntu
- **Baseline packages** — `curl`, `ca-certificates`, `gnupg`, `git`, `jq`, `unzip`
- **Kerberos support** — `krb5-user` package, for Kerberos authentication relevant to on-premises Active Directory integration

The script then installs these PowerShell modules to the system-wide (AllUsers) scope:

- `Microsoft.Graph.Authentication` — required base module for `Connect-MgGraph`; every other Graph submodule depends on it
- `Microsoft.Graph.Users` — Entra ID / Microsoft 365 user management
- `Microsoft.Graph.Groups` — Entra ID / Microsoft 365 group management
- `Microsoft.Graph.Identity.DirectoryManagement` — Entra ID directory/tenant-level objects (domains, organization info, etc.)
- `Microsoft.Graph.Applications` — Entra ID app registrations and service principals
- `Microsoft.Graph.Teams` — Microsoft Teams management via Graph
- `Microsoft.Graph.Sites` — SharePoint Online management via Graph
- `Microsoft.Graph.Mail` — Exchange/Microsoft 365 mail via Graph (complements the separate `ExchangeOnlineManagement` module, which handles full EXO administration)
- `ExchangeOnlineManagement` — Exchange Online administration
- `MicrosoftTeams` — Microsoft Teams management
- `Az` — Azure management
- `PnP.PowerShell` — SharePoint PnP operations

All modules are installed with `-Scope AllUsers` (system-wide, available to any container user) and are actively imported into the PowerShell all-users profile so every new PowerShell session in the container loads them automatically. Installation idempotently skips modules already present on subsequent runs, and the profile import entry is added only once and not duplicated on reruns. Because `-Scope AllUsers` requires elevated privileges, the module installation runs via `sudo` inside the container—no elevation is needed on the host during `install.sh`. These specific Microsoft.Graph submodules provide narrower, faster installation while covering the core admin scope: Entra ID, Teams, SharePoint, and mail.

### Note: No Local Active Directory Module

The Windows-only `ActiveDirectory` RSAT module has no Linux equivalent and cannot run under PowerShell 7. The bootstrap script deliberately omits it. To manage on-premises Active Directory from this container, use PowerShell remoting to a domain-joined Windows host that has RSAT installed:

```powershell
$session = New-PSSession -ComputerName <domain-host> -Credential $cred
Invoke-Command -Session $session -ScriptBlock { Get-ADUser ... }
```

## Home Directory Options

The installation script offers two modes for how the container manages your home directory.

### Using Your Existing Home

If you select "use existing home," the container mounts your current user home directory. This mode gives the container full access to your existing files, repositories, and configuration.

### Creating a Separate PWSHenv Home

If you select "create a separate PWSHenv home," the script creates a new, isolated home directory (default: `~/PWSHenv-home`) on the host. The container uses this dedicated directory as its home, keeping configuration and work separate from your host system.

When prompted, you may specify an alternate path for the new PWSHenv home. The script refuses paths that are `/` or your real user home to prevent accidental overwrites.

## Contributing

Contributions are welcome. Please open an issue to discuss your ideas before submitting code changes.

## Credits

PWSHenv builds on and depends on the following upstream projects:

- **Distrobox** — Container entry point and lifecycle management
- **Ubuntu** — Base container image (`ubuntu:24.04`)
- **PowerShell** — Shell and scripting language (Microsoft)
- **Microsoft.Graph.Authentication** — Microsoft Graph base authentication module
- **Microsoft.Graph.Users** — Microsoft Graph user management module
- **Microsoft.Graph.Groups** — Microsoft Graph group management module
- **Microsoft.Graph.Identity.DirectoryManagement** — Microsoft Graph directory management module
- **Microsoft.Graph.Applications** — Microsoft Graph applications module
- **Microsoft.Graph.Teams** — Microsoft Graph Teams module
- **Microsoft.Graph.Sites** — Microsoft Graph Sites module
- **Microsoft.Graph.Mail** — Microsoft Graph mail module
- **ExchangeOnlineManagement** — Exchange Online module
- **MicrosoftTeams** — Microsoft Teams module
- **Az** — Azure PowerShell module
- **PnP.PowerShell** — SharePoint PnP module
