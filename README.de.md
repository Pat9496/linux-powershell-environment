# PWSHenv

[![Shell: Bash](https://img.shields.io/badge/shell-bash-blue)](https://www.gnu.org/software/bash/)
[![PowerShell: 7](https://img.shields.io/badge/powershell-7-blue)](https://github.com/PowerShell/PowerShell)

Ein automatisiertes Installationsskript für eine Distrobox-basierte PowerShell 7-Umgebung, die für die Microsoft-Cloud-Administration optimiert ist.

[English version](README.md)

## Inhaltsverzeichnis

- [Über](#über)
- [Voraussetzungen](#voraussetzungen)
- [Erste Schritte](#erste-schritte)
  - [Das Installationsskript ausführen](#das-installationsskript-ausführen)
  - [Installationseingaben](#installationseingaben)
  - [Den Container betreten](#den-container-betreten)
  - [Host-Befehl und Eintrag im Anwendungsmenü](#host-befehl-und-eintrag-im-anwendungsmenü)
- [PowerShell-Konfiguration zurücksetzen](#powershell-konfiguration-zurücksetzen)
- [Bereinigte Neuinstallation](#bereinigte-neuinstallation)
- [PowerShell und Module aktualisieren](#powershell-und-module-aktualisieren)
- [Was wird installiert](#was-wird-installiert)
  - [PowerShell-Module](#powershell-module)
  - [Hinweis: Kein lokales Active Directory-Modul](#hinweis-kein-lokales-active-directory-modul)
  - [Starship Prompt-Integration](#starship-prompt-integration)
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

### Host-Befehl und Eintrag im Anwendungsmenü

Während der Installation wird ein `powershell`-Wrapper-Skript in `~/.local/bin/powershell` auf dem Host-System installiert. Dies ermöglicht das direkte Starten von PowerShell vom Terminal aus, ohne den vollständigen `distrobox enter`-Befehl eingeben zu müssen:

```bash
powershell
```

Das Wrapper-Skript wird in den `PWSHenv`-Container ausgeführt und startet PowerShell. Wird das Wrapper-Skript von innerhalb des `PWSHenv`-Containers selbst ausgeführt (sein `~/.local/bin` ist dort ebenfalls sichtbar, da Distrobox das gesamte Host-Dateisystem freigibt), erkennt das Wrapper-Skript dies und startet `pwsh` direkt, statt zu versuchen, den Container erneut zu betreten, wodurch Rekursion vermieden wird.

**`~/.local/bin` zu PATH hinzufügen:** Falls `~/.local/bin` nicht bereits in `PATH` aufgenommen ist, wird das Installationsskript wie folgt verfahren:

- **Mit chezmoi:** Falls chezmoi auf dem Host-System installiert und initialisiert ist (ein Source-Verzeichnis vorhanden ist) und `~/.local/bin` nicht bereits in `PATH` aufgenommen ist, fordert das Skript zur Bestätigung auf, bevor Änderungen vorgenommen werden:

```
chezmoi is installed and initialized. The following change can be captured:
  File: <rc_file>
  Line: export PATH="${HOME}/.local/bin:$PATH"
  Command: chezmoi <add|re-add> <rc_file>
Proceed? [y/N]:
```

Bei Antwort „ja" fügt das Skript die Zeile zur Shell-Startdatei hinzu (`~/.bashrc` bei Bash, `~/.zshrc` bei Zsh) und erfasst diese Änderung im Source-State von chezmoi mit `chezmoi add` (oder `chezmoi re-add`, falls die Startdatei bereits von chezmoi verwaltet wurde). Die Änderung ist nun Teil des chezmoi-Source-State und wird wie jede andere chezmoi-verwaltete Änderung angewendet, wenn `chezmoi apply` auf diesem oder anderen Rechnern ausgeführt wird (nach der Synchronisierung des Source-Repository). Bei Ablehnung fällt das Skript stattdessen auf die manuelle Erinnerung weiter unten zurück.
- **Ohne chezmoi:** Falls chezmoi nicht installiert oder nicht initialisiert ist, gibt das Skript eine Erinnerung aus. Die folgende Zeile zur Shell-Startdatei hinzufügen:

```bash
export PATH="${HOME}/.local/bin:$PATH"
```

**Eintrag im Desktop-Anwendungsmenü:** Das Bootstrap-Skript erstellt auch einen PowerShell-Eintrag im Anwendungsmenü. Eine `.desktop`-Datei wird innerhalb des Containers erstellt und über `distrobox-export --app` in das Anwendungsmenü des Hosts exportiert (GNOME Launcher, KDE Plasma App-Menü, etc.). PowerShell wird als „PowerShell (on PWSHenv)" angezeigt und kann zusammen mit anderen installierten Anwendungen vom Anwendungsstarter aus gestartet werden.

Dieser Desktop-Export ist nicht kritisch. Falls `distrobox-export` innerhalb des Containers nicht verfügbar ist oder fehlschlägt, warnt das Bootstrap-Skript und fährt ohne diesen fort – der `powershell`-Befehl und `distrobox enter` bleiben vollständig funktionsfähig.

## PowerShell-Konfiguration zurücksetzen

Um die PowerShell-Benutzerkonfiguration innerhalb des Containers zurückzusetzen, ohne den gesamten Container neu zu erstellen, das `--reset-config`-Flag verwenden:

```bash
./install.sh --reset-config
```

Das Flag erfordert, dass der `PWSHenv`-Container bereits existiert. Das Skript fordert zur Bestätigung auf und entfernt dann `~/.config/powershell`, `~/.cache/powershell` und `~/.local/share/powershell` innerhalb des Containers (wobei das Profil, der Modulzustand und die Historie gelöscht werden), ohne andere Komponenten zu berühren oder neu zu erstellen.

Falls chezmoi installiert und initialisiert ist und die Shell-Startdatei bereits von chezmoi verwaltet wird, bietet `--reset-config` auch an, die PATH-Konfigurationszeile zu aktualisieren. Das Skript zeigt die gleiche Bestätigungsaufforderung wie beim initialen Setup und fragt, ob die Zeile `export PATH="${HOME}/.local/bin:$PATH"` aus der Startdatei entfernt und erneut hinzugefügt und die Änderung mit chezmoi erneut erfasst werden soll. Bei Ablehnung wird die Startdatei nicht berührt. Falls chezmoi nicht verwendet wird oder die Startdatei nicht von chezmoi verwaltet wird, gilt dieses Verhalten nicht – `--reset-config` verhält sich genau wie oben beschrieben, ohne zusätzliche Änderungen.

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

## PowerShell und Module aktualisieren

Zum Aktualisieren von PowerShell, Basis-apt-Paketen und bereits installierten PowerShell-Modulen im bestehenden `PWSHenv`-Container das `--update`-Flag verwenden:

```bash
./install.sh --update
```

Das Flag erfordert, dass der `PWSHenv`-Container bereits existiert. Das Skript führt `apt-get update && apt-get upgrade -y` innerhalb des Containers aus, um alle Pakete zu aktualisieren (einschließlich PowerShell selbst, da es über Microsofts apt-Repository installiert wurde), und ermittelt dann und aktualisiert alle PowerShell-Module, die derzeit installiert sind, über `Get-InstalledModule` und `Update-Module`.

Das `--update`-Flag erstellt den Container bewusst nicht neu und berührt keine bestehende Konfiguration – das Profil für alle Benutzer, Modul-Auto-Import-Einträge, chezmoi-State, Starship-Integration und Home-Verzeichnis bleiben unangetastet. Dies ist eine reine Versions-Bump-Operation ohne Bestätigungsaufforderungen.

Da `--update` installierte Module dynamisch ermittelt, statt eine feste Modulliste zu führen, deckt es natürlich alle Module ab, die jemals im Container installiert wurden, einschließlich Module, die nach dem initialen Setup selbst installiert werden. Falls später ein benutzerdefiniertes PowerShell-Modul hinzugefügt wird, wird es beim nächsten `--update`-Lauf zusammen mit den Basis-Modulen ermittelt und aktualisiert.

Das `--update`-Flag kann nicht mit `--reset-config`, `--clean-reinstall`, `--use-starship` oder `--no-starship` kombiniert werden.

## Was wird installiert

Das Bootstrap-Skript innerhalb des Containers installiert Folgendes:

- **PowerShell 7** — Installiert über Microsofts offizielles apt-Repository für Ubuntu
- **Basis-Pakete** — `curl`, `ca-certificates`, `gnupg`, `git`, `jq`, `unzip`
- **Kerberos-Unterstützung** — das Paket `krb5-user` für Kerberos-Authentifizierung relevant für die lokale Active Directory-Integration

### PowerShell-Module

Das Skript installiert diese PowerShell-Module im systemweiten (AllUsers) Umfang. Sechs von ihnen werden bei jeder Sitzung automatisch geladen; die anderen sechs sind installiert, werden aber bedarfsweise importiert.

**Bei jedem Sitzungsstart automatisch importiert:**

- `Microsoft.Graph.Authentication` — erforderliches Basis-Modul für `Connect-MgGraph`; jedes andere Graph-Submodul hängt davon ab
- `Microsoft.Graph.Users` — Entra ID- / Microsoft 365-Benutzerverwaltung
- `Microsoft.Graph.Groups` — Entra ID- / Microsoft 365-Gruppenverwaltung
- `MicrosoftTeams` — Microsoft Teams-Verwaltung
- `ExchangeOnlineManagement` — Exchange Online-Administration
- `PnP.PowerShell` — SharePoint PnP-Operationen

**Installiert, bedarfsweise importiert:**

- `Microsoft.Graph.Identity.DirectoryManagement` — Entra ID-Verzeichnis- / Mandanten-Objekte (Domains, Organisationsinformationen, etc.)
- `Microsoft.Graph.Applications` — Entra ID-App-Registrierungen und Service Principals
- `Microsoft.Graph.Teams` — Microsoft Teams-Verwaltung via Graph
- `Microsoft.Graph.Sites` — SharePoint Online-Verwaltung via Graph
- `Microsoft.Graph.Mail` — Exchange / Microsoft 365-Mail via Graph (ergänzt das separate `ExchangeOnlineManagement`-Modul, das vollständige EXO-Administration übernimmt)
- `Az` — Azure-Verwaltung

Alle Module werden mit `-Scope AllUsers` (systemweit, verfügbar für jeden Container-Benutzer) installiert. Die Module der ersten Gruppe werden aktiv ins PowerShell-Profil für alle Benutzer importiert, sodass jede neue Sitzung sie automatisch lädt. Die Module der zweiten Gruppe bleiben vollständig installiert und verwendbar; sie werden bei Bedarf mit `Import-Module <name>` importiert. Diese Aufteilung optimiert die PowerShell-Sitzungsstartzeit – mehrere Module, insbesondere `Az` und `MicrosoftTeams`, sind langsam beim Importieren, und das Laden aller zwölf Module bei jedem Sitzungsstart verlangsamte ihn spürbar. Die Installation überspringt Module idempotent, falls bereits vorhanden bei nachfolgenden Läufen, und der Profil-Import-Eintrag wird nur einmal hinzugefügt und bei erneuten Läufen nicht dupliziert. Da `-Scope AllUsers` erhöhte Privilegien erfordert, wird die Modul-Installation via `sudo` innerhalb des Containers ausgeführt – auf dem Host ist während `install.sh` keine Erhöhung erforderlich. Diese speziellen Microsoft.Graph-Submodule ermöglichen eine engere, schnellere Installation und decken gleichzeitig den zentralen Admin-Umfang ab: Entra ID, Teams, SharePoint und Mail.

### Hinweis: Kein lokales Active Directory-Modul

Das ausschließlich für Windows verfügbare RSAT-Modul `ActiveDirectory` hat kein Linux-Äquivalent und kann nicht unter PowerShell 7 ausgeführt werden. Das Bootstrap-Skript lässt es bewusst weg. Um lokale Active Directory-Umgebungen von diesem Container aus zu verwalten, PowerShell Remoting zu einem der Domäne angehörenden Windows-Host mit installiertem RSAT verwenden:

```powershell
$session = New-PSSession -ComputerName <domain-host> -Credential $cred
Invoke-Command -Session $session -ScriptBlock { Get-ADUser ... }
```

### Starship Prompt-Integration

PWSHenv kann optional die Starship Cross-Shell-Prompt-Integration in PowerShell durchführen. Dies wird mit zwei sich gegenseitig ausschließenden Befehlszeilenflaggen gesteuert:

- `--use-starship` — Erzwungene Aktivierung der Starship-Prompt-Integration.
- `--no-starship` — Erzwungene Deaktivierung der Integration.

Falls weder Flag angegeben ist, fordert das Skript interaktiv auf:

```
Enable Starship prompt integration for PowerShell? [Y/n]:
```

Die angezeigte Standardantwort ([Y/n]-Format, wobei der Großbuchstabe die Voreinstellung angibt) wird basierend darauf vorausgefüllt, ob der Befehl `starship` in der `PATH` des Hosts vorhanden ist – falls gefunden, ist die Voreinstellung ja; falls nicht gefunden, ist die Voreinstellung nein. Es ist immer möglich, auf eine beliebige Weise zu antworten und die vorgeschlagene Voreinstellung zu überschreiben.

Diese Flags wirken sich nur auf einen normalen Lauf oder `--clean-reinstall` aus (beide führen das Modul-Installationsskript innerhalb des Containers aus). Das Kombinieren eines der Flags mit `--reset-config` ist ein Fehler, da `--reset-config` nie das Modul-Installationsskript erneut ausführt, daher hätte das Flag keine Wirkung.

Bei Aktivierung wird diese Zeile zum PowerShell-Profil für alle Benutzer innerhalb des Containers hinzugefügt:

```powershell
if (Get-Command starship -ErrorAction SilentlyContinue) { Invoke-Expression (&starship init powershell) }
```

Diese Zeile wird zur Laufzeit geschützt – sie prüft bei jedem PowerShell-Sitzungsstart auf den Befehl `starship` und tut stillschweigend nichts, falls `starship` in diesem Moment nicht erreichbar ist. Dies ist wichtig, da die Sichtbarkeit einer auf dem Host installierten `starship`-Binärdatei innerhalb des Containers davon abhängt, welcher Home-Verzeichnis-Modus bei der Installation ausgewählt wurde (Bestehendes Home vs. separates PWSHenv-Home) und wie die Container-`PATH` konfiguriert ist. Da die Erkennung zum Installationszeitpunkt die Verfügbarkeit zum Container-Zeitpunkt nicht perfekt vorhersagen kann, stellt der Laufzeit-Schutz sicher, dass die Starship-Integration eine PowerShell-Sitzung nie bricht, falls die `starship`-Binärdatei später nicht mehr verfügbar ist.

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
