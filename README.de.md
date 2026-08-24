[![Shell: Bash](https://img.shields.io/badge/shell-bash-blue)](https://www.gnu.org/software/bash/)
[![PowerShell: 7](https://img.shields.io/badge/powershell-7-blue)](https://github.com/PowerShell/PowerShell)

[English version](README.md)

## Inhaltsverzeichnis

- [Über](#über)
- [Voraussetzungen](#voraussetzungen)
- [Erste Schritte](#erste-schritte)
  - [Das Installationsskript ausführen](#das-installationsskript-ausführen)
  - [Installationseingaben](#installationseingaben)
  - [Den Container betreten](#den-container-betreten)
- [PowerShell-Konfiguration zurücksetzen](#powershell-konfiguration-zurücksetzen)
- [Bereinigte Neuinstallation](#bereinigte-neuinstallation)
- [Was wird installiert](#was-wird-installiert)
- [Optionen für das Home-Verzeichnis](#optionen-für-das-home-verzeichnis)
  - [Das bestehende Home verwenden](#das-bestehende-home-verwenden)
  - [Ein separates PWSHenv-Home erstellen](#ein-separates-pwshenv-home-erstellen)
- [Mitwirkung](#mitwirkung)
- [Danksagung](#danksagung)

## Über

PWSHenv ist ein automatisiertes Installationsskript für eine Distrobox-basierte PowerShell 7-Umgebung, die für die Microsoft-Cloud-Administration optimiert ist. Es konfiguriert einen Container mit PowerShell 7 und den Modulen, die erforderlich sind, um Entra ID, Microsoft 365 und Mandanten-Ressourcen zu verwalten. Für lokale Active Directory-Umgebungen unterstützt der Container PowerShell Remoting zu einem der Domäne angehörenden Windows-Host. Das Installationsskript wird auf dem Host ausgeführt und erstellt sowie stellt einen Container mit allen erforderlichen Werkzeugen bereit.

## Voraussetzungen

Auf dem Host-System müssen folgende Komponenten vorhanden sein:

- Ein Linux-System (jede Distribution)
- `distrobox` installiert
- Entweder `podman` oder `docker` als Container-Runtime verfügbar

Das Installationsskript selbst ist eigenständig und richtet alles weitere innerhalb des Containers ein.

## Erste Schritte

### Das Installationsskript ausführen

Das Repository auf dem Host klonen und dann das Installationsskript ausführen:

```bash
git clone <repository-url>
cd PWSHenv
./install.sh
```

Das Skript überprüft, ob `distrobox` und `podman`/`docker` auf dem Host vorhanden sind, und führt dann durch den Konfigurationsprozess. Der Container wird immer mit dem fixen Namen `PWSHenv` unter Verwendung des Images `ubuntu:24.04` erstellt.

**Warum Ubuntu 24.04?** Microsoft veröffentlicht PowerShell-Pakete für Ubuntu am schnellsten über sein offizielles apt-Repository. Die 24.04-Version ist die aktuelle Ubuntu LTS-Version und stellt langfristige Paket-Stabilität und Support sicher.

### Installationseingaben

Während der Installation werden die folgenden Informationen abgefragt:

1. **Home-Verzeichnis-Modus** — Wahl zwischen der Verwendung des bestehenden Benutzer-Home oder der Erstellung eines separaten PWSHenv-Home (Details in [Optionen für das Home-Verzeichnis](#optionen-für-das-home-verzeichnis) weiter unten).

**Container-Neuanlage:** Das Skript zerstört und erstellt den Container bei jedem Lauf neu. Dies ist beabsichtigt — es verhindert, dass eine halb angewandte vorherige Installation oder abweichende Pakete stillschweigend mitgenommen werden. Existiert bereits ein Container mit dem Namen `PWSHenv`, warnt das Skript und entfernt ihn vor der Erstellung eines neuen.

### Den Container betreten

Nach Abschluss der Installation wird der Container mit folgendem Befehl betreten:

```bash
distrobox enter PWSHenv
```

## PowerShell-Konfiguration zurücksetzen

Um die PowerShell-Benutzerkonfiguration innerhalb des Containers zurückzusetzen, ohne den gesamten Container neu zu erstellen, das `--reset-config`-Flag verwenden:

```bash
./install.sh --reset-config
```

Das Flag erfordert, dass der `PWSHenv`-Container bereits existiert. Das Skript fordert zur Bestätigung auf und entfernt dann `~/.config/powershell`, `~/.cache/powershell` und `~/.local/share/powershell` innerhalb des Containers (wobei das Profil, der Modulzustand und die Historie gelöscht werden), ohne andere Komponenten zu berühren oder neu zu erstellen.

Um die Hilfemeldung anzuzeigen und alle verfügbaren Flags zu sehen:

```bash
./install.sh -h
```

oder

```bash
./install.sh --help
```

## Bereinigte Neuinstallation

Zum Zerstören und Neuerstellen des Containers unter gleichzeitiger Bereinigung der PowerShell-Zustandsverzeichnisse das `--clean-reinstall`-Flag verwenden:

```bash
./install.sh --clean-reinstall
```

Dies führt denselben Gesamtablauf wie ein standardmäßiger `./install.sh`-Lauf durch (Host-Voraussetzungsprüfungen, Home-Verzeichnis-Modus-Abfrage, Container-Erstellung und Bootstrap), bereinigt aber zuvor die PowerShell-Zustandsverzeichnisse (`~/.config/powershell`, `~/.cache/powershell` und `~/.local/share/powershell`) unter dem aufgelösten Home-Pfad – das echte Host-Home im Modus „Bestehendes Home verwenden" oder das separate PWSHenv-Home im Modus „Separates Home erstellen". Dies ergibt einen vollständig sauberen Zustand, als hätte PowerShell nie installiert.

Das Skript fragt zur expliziten Bestätigung auf, bevor destruktive Aktionen durchgeführt werden, mit klarer Angabe, dass der Container zerstört und neu erstellt wird und dass die drei Zustandsverzeichnisse permanent gelöscht werden. Wird abgelehnt, beendet sich das Skript, ohne den Container oder Dateien zu berühren.

Im Gegensatz zu `--reset-config`, das PowerShell-Zustand auf einem bestehenden Container löscht, ohne ihn neu zu erstellen, zerstört und rekonstruiert `--clean-reinstall` den Container auch, für einen vollständig sauberen Zustand.

Die Flags `--clean-reinstall` und `--reset-config` schließen sich gegenseitig aus – das Übergeben beider ist ein Fehler.

## Was wird installiert

Das Bootstrap-Skript innerhalb des Containers installiert Folgendes:

- **PowerShell 7** — Installiert über Microsofts offizielles apt-Repository für Ubuntu
- **Basis-Pakete** — `curl`, `ca-certificates`, `gnupg`, `git`, `jq`, `unzip`
- **Kerberos-Unterstützung** — das Paket `krb5-user` für Kerberos-Authentifizierung relevant für die lokale Active Directory-Integration

Das Skript installiert dann diese PowerShell-Module im systemweiten (AllUsers) Umfang:

- `Microsoft.Graph.Authentication` — erforderliches Basis-Modul für `Connect-MgGraph`; jedes andere Graph-Submodul hängt davon ab
- `Microsoft.Graph.Users` — Entra ID- / Microsoft 365-Benutzerverwaltung
- `Microsoft.Graph.Groups` — Entra ID- / Microsoft 365-Gruppenverwaltung
- `Microsoft.Graph.Identity.DirectoryManagement` — Entra ID-Verzeichnis- / Mandanten-Objekte (Domains, Organisationsinformationen, etc.)
- `Microsoft.Graph.Applications` — Entra ID-App-Registrierungen und Service Principals
- `Microsoft.Graph.Teams` — Microsoft Teams-Verwaltung via Graph
- `Microsoft.Graph.Sites` — SharePoint Online-Verwaltung via Graph
- `Microsoft.Graph.Mail` — Exchange / Microsoft 365-Mail via Graph (ergänzt das separate `ExchangeOnlineManagement`-Modul, das vollständige EXO-Administration übernimmt)
- `ExchangeOnlineManagement` — Exchange Online-Administration
- `MicrosoftTeams` — Microsoft Teams-Verwaltung
- `Az` — Azure-Verwaltung
- `PnP.PowerShell` — SharePoint PnP-Operationen

Alle Module werden mit `-Scope AllUsers` (systemweit, verfügbar für jeden Container-Benutzer) installiert und aktiv ins PowerShell-Profil für alle Benutzer importiert, sodass jede neue PowerShell-Sitzung im Container sie automatisch lädt. Die Installation überspringt Module idempotent, falls bereits vorhanden bei nachfolgenden Läufen, und der Profil-Import-Eintrag wird nur einmal hinzugefügt und bei erneuten Läufen nicht dupliziert. Da `-Scope AllUsers` erhöhte Privilegien erfordert, wird die Modul-Installation via `sudo` innerhalb des Containers ausgeführt – auf dem Host ist während `install.sh` keine Erhöhung erforderlich. Diese speziellen Microsoft.Graph-Submodule ermöglichen eine engere, schnellere Installation und decken gleichzeitig den zentralen Admin-Umfang ab: Entra ID, Teams, SharePoint und Mail.

### Hinweis: Kein lokales Active Directory-Modul

Das ausschließlich für Windows verfügbare RSAT-Modul `ActiveDirectory` hat kein Linux-Äquivalent und kann nicht unter PowerShell 7 ausgeführt werden. Das Bootstrap-Skript lässt es bewusst weg. Um lokale Active Directory-Umgebungen von diesem Container aus zu verwalten, PowerShell Remoting zu einem der Domäne angehörenden Windows-Host mit installiertem RSAT verwenden:

```powershell
$session = New-PSSession -ComputerName <domain-host> -Credential $cred
Invoke-Command -Session $session -ScriptBlock { Get-ADUser ... }
```

## Optionen für das Home-Verzeichnis

Das Installationsskript bietet zwei Modi, wie der Container das Home-Verzeichnis verwaltet.

### Das bestehende Home verwenden

Wird „Bestehendes Home verwenden" ausgewählt, bindet der Container das aktuelle Benutzer-Home-Verzeichnis ein. Dieser Modus gibt dem Container vollständigen Zugriff auf bestehende Dateien, Repositories und Konfigurationen.

### Ein separates PWSHenv-Home erstellen

Wird „Ein separates PWSHenv-Home erstellen" ausgewählt, erstellt das Skript ein neues, isoliertes Home-Verzeichnis (Standard: `~/PWSHenv-home`) auf dem Host. Der Container verwendet dieses dedizierte Verzeichnis als sein Home-Verzeichnis, wodurch Konfiguration und Arbeit vom Host-System getrennt bleiben.

Auf Nachfrage kann ein alternativer Pfad für das neue PWSHenv-Home angegeben werden. Das Skript lehnt Pfade ab, die `/` oder das echte Benutzer-Home sind, um versehentliche Überschreibungen zu verhindern.

## Mitwirkung

Beiträge sind willkommen. Ein Issue sollte erstellt werden, um Ideen vor der Einreichung von Code-Änderungen zu diskutieren.

## Danksagung

PWSHenv basiert auf und hängt von folgenden Upstream-Projekten ab:

- **Distrobox** — Container-Einstiegspunkt und Lebenszyklusmanagement
- **Ubuntu** — Basis-Container-Image (`ubuntu:24.04`)
- **PowerShell** — Shell und Scripting-Sprache (Microsoft)
- **Microsoft.Graph.Authentication** — Microsoft Graph-Basis-Authentifizierungsmodul
- **Microsoft.Graph.Users** — Microsoft Graph-Benutzerverwaltungsmodul
- **Microsoft.Graph.Groups** — Microsoft Graph-Gruppenverwaltungsmodul
- **Microsoft.Graph.Identity.DirectoryManagement** — Microsoft Graph-Verzeichnisverwaltungsmodul
- **Microsoft.Graph.Applications** — Microsoft Graph-Anwendungenmodul
- **Microsoft.Graph.Teams** — Microsoft Graph-Teams-Modul
- **Microsoft.Graph.Sites** — Microsoft Graph-Sites-Modul
- **Microsoft.Graph.Mail** — Microsoft Graph-Mail-Modul
- **ExchangeOnlineManagement** — Exchange Online-Modul
- **MicrosoftTeams** — Microsoft Teams-Modul
- **Az** — Azure PowerShell-Modul
- **PnP.PowerShell** — SharePoint PnP-Modul
