# PWSHenv

[![Shell: Bash](https://img.shields.io/badge/shell-bash-blue)](https://www.gnu.org/software/bash/)
[![PowerShell: 7](https://img.shields.io/badge/powershell-7-blue)](https://github.com/PowerShell/PowerShell)

An automated setup script for a Distrobox-based PowerShell 7 environment tailored for Microsoft-cloud administration.

[Deutsche Version](README.de.md)

## Table of Contents

- [About](#about)
- [Requirements](#requirements)
- [Getting Started](#getting-started)
  - [Running the Installation Script](#running-the-installation-script)
  - [Installation Prompts](#installation-prompts)
  - [Entering the Container](#entering-the-container)
  - [Host Command and Application Menu Entry](#host-command-and-application-menu-entry)
- [Resetting PowerShell Configuration](#resetting-powershell-configuration)
- [Clean Reinstall](#clean-reinstall)
- [Updating PowerShell and Modules](#updating-powershell-and-modules)
- [What Gets Installed](#what-gets-installed)
  - [PowerShell Modules](#powershell-modules)
  - [Note: No Local Active Directory Module](#note-no-local-active-directory-module)
  - [Starship Prompt Integration](#starship-prompt-integration)
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

### Host Command and Application Menu Entry

During installation, a `powershell` wrapper script is installed to `~/.local/bin/powershell` on your host system. This lets you launch PowerShell directly from your terminal without typing the full `distrobox enter` command:

```bash
powershell
```

The wrapper execs into the `PWSHenv` container and starts PowerShell. If you run it from inside the `PWSHenv` container itself (its `~/.local/bin` is visible there too, since Distrobox shares the whole host filesystem), the wrapper detects this and execs `pwsh` directly instead of trying to re-enter the container, avoiding recursion.

**Adding `~/.local/bin` to PATH:** If `~/.local/bin` is not already on your `PATH`, the installation script handles it as follows:

- **With chezmoi:** If chezmoi is installed and initialized on your host system (has a source directory) and `~/.local/bin` is not yet on your PATH, the script prompts you for confirmation before making any change:

```
chezmoi is installed and initialized. The following change can be captured:
  File: <rc_file>
  Line: export PATH="${HOME}/.local/bin:$PATH"
  Command: chezmoi <add|re-add> <rc_file>
Proceed? [y/N]:
```

If you answer yes, the script appends the line to your shell startup file (`~/.bashrc` if you use Bash, `~/.zshrc` if you use Zsh) and captures this change into chezmoi's source state using `chezmoi add` (or `chezmoi re-add` if the startup file was already chezmoi-managed). The change is now part of your chezmoi source state and will apply like any other chezmoi-managed change when you run `chezmoi apply` on this or other machines (after syncing your source repository). If you decline, the script falls back to the manual reminder below instead.
- **Without chezmoi:** If chezmoi is not installed or not initialized, the script prints a reminder. Manually add this line to your shell startup file:

```bash
export PATH="${HOME}/.local/bin:$PATH"
```

**Desktop application menu entry:** The bootstrap script also creates a PowerShell application menu entry. A `.desktop` file is created inside the container and exported to your host's application menu (GNOME launcher, KDE Plasma app menu, etc.) via `distrobox-export --app`. PowerShell appears as "PowerShell (on PWSHenv)" and can be launched from your application launcher alongside any other installed applications.

This desktop export is non-critical. If `distrobox-export` is unavailable inside the container or fails, the bootstrap script warns and continues without it—the `powershell` command and `distrobox enter` remain fully functional.

## Resetting PowerShell Configuration

To reset PowerShell's user configuration inside the container without recreating the entire container, use the `--reset-config` flag:

```bash
./install.sh --reset-config
```

This flag requires the `PWSHenv` container to already exist. The script will prompt for confirmation, then remove `~/.config/powershell`, `~/.cache/powershell`, and `~/.local/share/powershell` inside the container (erasing the profile, module state, and history) without touching or rebuilding anything else.

If chezmoi is installed and initialized, and your shell startup file is already chezmoi-managed, `--reset-config` also offers to refresh the PATH configuration line. The script shows the same confirmation prompt as during initial setup and asks whether to remove and re-append `export PATH="${HOME}/.local/bin:$PATH"` to your startup file and re-capture the change with chezmoi. If you decline, the startup file is not touched. If chezmoi is not in use, or the startup file is not managed by chezmoi, this behavior does not apply—`--reset-config` behaves exactly as described above with no additional changes.

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

## Updating PowerShell and Modules

To update PowerShell, baseline apt packages, and already-installed PowerShell modules inside the existing `PWSHenv` container in place, use the `--update` flag:

```bash
./install.sh --update
```

This flag requires the `PWSHenv` container to already exist. The script runs `apt-get update && apt-get upgrade -y` inside the container to update all packages (including PowerShell itself, since it was installed via Microsoft's apt repository), then discovers and updates whatever PowerShell modules are currently installed via `Get-InstalledModule` and `Update-Module`.

The `--update` flag deliberately does not recreate the container and does not touch existing configuration—the all-users profile, module auto-import entries, chezmoi state, Starship integration, and home directory are left untouched. This is purely a version-bump operation with no prompts.

Because `--update` discovers installed modules dynamically rather than maintaining a fixed module list, it naturally covers any module ever installed in the container, including modules you install yourself after the initial setup. If you add a custom PowerShell module later, the next `--update` run will discover and update it alongside the baseline modules.

The `--update` flag cannot be combined with `--reset-config`, `--clean-reinstall`, `--use-starship`, or `--no-starship`.

## What Gets Installed

The bootstrap script inside the container installs the following:

- **PowerShell 7** — Installed via Microsoft's official apt repository for Ubuntu
- **Baseline packages** — `curl`, `ca-certificates`, `gnupg`, `git`, `jq`, `unzip`
- **Kerberos support** — `krb5-user` package, for Kerberos authentication relevant to on-premises Active Directory integration

### PowerShell Modules

The script installs these PowerShell modules to the system-wide (AllUsers) scope. Six of them auto-load in every session; the other six are installed but imported on demand.

**Auto-imported at every session start:**

- `Microsoft.Graph.Authentication` — required base module for `Connect-MgGraph`; every other Graph submodule depends on it
- `Microsoft.Graph.Users` — Entra ID / Microsoft 365 user management
- `Microsoft.Graph.Groups` — Entra ID / Microsoft 365 group management
- `MicrosoftTeams` — Microsoft Teams management
- `ExchangeOnlineManagement` — Exchange Online administration
- `PnP.PowerShell` — SharePoint PnP operations

**Installed, imported on demand:**

- `Microsoft.Graph.Identity.DirectoryManagement` — Entra ID directory/tenant-level objects (domains, organization info, etc.)
- `Microsoft.Graph.Applications` — Entra ID app registrations and service principals
- `Microsoft.Graph.Teams` — Microsoft Teams management via Graph
- `Microsoft.Graph.Sites` — SharePoint Online management via Graph
- `Microsoft.Graph.Mail` — Exchange/Microsoft 365 mail via Graph (complements the separate `ExchangeOnlineManagement` module, which handles full EXO administration)
- `Az` — Azure management

All modules are installed with `-Scope AllUsers` (system-wide, available to any container user). The auto-imported modules are actively imported into the PowerShell all-users profile so every new session loads them automatically. The on-demand modules remain fully installed and usable; import them with `Import-Module <name>` when you need them. This split optimizes session startup time—several modules, especially `Az` and `MicrosoftTeams`, are slow to import, and eagerly loading all twelve into every session was sluggish. Installation idempotently skips modules already present on subsequent runs, and the profile import entries are added only once and not duplicated on reruns. Because `-Scope AllUsers` requires elevated privileges, the module installation runs via `sudo` inside the container—no elevation is needed on the host during `install.sh`. These specific Microsoft.Graph submodules provide narrower, faster installation while covering the core admin scope: Entra ID, Teams, SharePoint, and mail.

### Note: No Local Active Directory Module

The Windows-only `ActiveDirectory` RSAT module has no Linux equivalent and cannot run under PowerShell 7. The bootstrap script deliberately omits it. To manage on-premises Active Directory from this container, use PowerShell remoting to a domain-joined Windows host that has RSAT installed:

```powershell
$session = New-PSSession -ComputerName <domain-host> -Credential $cred
Invoke-Command -Session $session -ScriptBlock { Get-ADUser ... }
```

### Starship Prompt Integration

PWSHenv can optionally integrate the Starship cross-shell prompt into PowerShell. You control this with two mutually exclusive command-line flags:

- `--use-starship` — Force-enable Starship prompt integration.
- `--no-starship` — Force-disable it.

If neither flag is given, the script prompts you interactively:

```
Enable Starship prompt integration for PowerShell? [Y/n]:
```

The default answer shown ([Y/n] format, with the capital letter indicating the default) is pre-filled based on whether the `starship` command is found on your host's `PATH`—if found, the default is yes; if not found, the default is no. You can always answer either way, overriding the suggested default.

These flags only take effect on a plain run or `--clean-reinstall` (both of which run the module installer inside the container). Combining either flag with `--reset-config` is an error, because `--reset-config` never re-runs the module installer, so the flag would have no effect.

When enabled, the script adds this line to PowerShell's all-users profile inside the container:

```powershell
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (&starship init powershell) }
```

This line is runtime-guarded—it checks for the `starship` command at each PowerShell session startup and silently does nothing if `starship` is not reachable at that moment. This matters because whether a host-installed `starship` binary is visible inside the container depends on which home-directory mode was chosen at install time (existing home vs. separate PWSHenv home) and how your container's PATH is configured. Because host-time detection cannot perfectly predict container-time availability, the runtime guard ensures Starship integration never breaks a PowerShell session if the binary becomes unavailable later.

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
