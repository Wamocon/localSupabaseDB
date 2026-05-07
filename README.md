# localSupabaseDB

Template-Repository für lokale Supabase-Entwicklungsumgebungen. Jede Next.js-Web-App bekommt eine eigene Kopie dieses Repos, damit lokal ohne Supabase-Cloud-Projekt entwickelt werden kann.

## Voraussetzungen

Die folgenden Tools müssen **einmalig pro Entwickler-Rechner** installiert werden und gelten dann für alle Apps.

### 1) Docker Desktop

- Offizielle Seite: https://www.docker.com/products/docker-desktop/
- macOS: Docker Desktop installieren und starten
- Windows: Docker Desktop installieren (WSL2 aktivieren)
- Linux: Docker Engine / Docker Desktop gemäß offizieller Anleitung installieren

### 2) Supabase CLI

Offizielle Doku: https://supabase.com/docs/guides/cli

Installationswege:

```bash
# macOS (Homebrew)
brew install supabase/tap/supabase

# npm (plattformübergreifend)
npm install supabase --save-dev

# direkter Download (GitHub Releases)
# siehe: https://github.com/supabase/cli/releases
```

### 3) Node.js

- Node.js >= 18

> Wichtig: In diesem Setup werden die Ports **3000–3999 für Next.js Apps reserviert**. Dieses Template nutzt ausschließlich Supabase-Ports im **54000er Bereich** (Start bei 54321).

> **Windows-Hinweis:** Verwende die **PowerShell-Skripte** (`.ps1`) – diese laufen direkt im VS Code Terminal.  
> Die Bash-Skripte (`.sh`) funktionieren zusätzlich in Git Bash, falls benötigt.

---

## Konzept (kurz erklärt)

- Dieses Repository startet lokal eine vollständige Supabase-Instanz per Docker + Supabase CLI.
- Das Setup ist kompatibel zu Supabase Cloud über dieselben Variablen:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`
- Jede App hat ihren eigenen Namen (`--app <name>`), der als Docker-Volume-Name dient.
- Alle App-Daten (Schemas, Tabellen, Datensätze) bleiben dauerhaft im Docker-Volume gespeichert und können jederzeit wieder geladen werden.
- Port-Philosophie:
  - Supabase lokal: 54321+ (54000er Bereich)
  - Next.js Apps lokal: 3000–3999

---

## App-Daten und Volumes verstehen

Supabase speichert alle Daten einer lokalen Instanz in einem **Docker-Volume**, das nach dem App-Namen benannt ist:

```
supabase_db_<app-name>   ← enthält alle Schemas, Tabellen, Datensätze
```

Das bedeutet:
- Jede App hat ihre eigenen isolierten Daten
- Beim Stoppen bleiben die Daten erhalten
- Beim nächsten Start mit demselben `--app <name>` werden die Daten automatisch wiederhergestellt
- Verschiedene Apps stören sich gegenseitig nicht

---

## Erstes Setup einer neuen App (Schritt für Schritt)

### Schritt 1 – Repository klonen

```bash
git clone https://github.com/<deine-org-oder-user>/<dein-repo-name>.git
cd <dein-repo-name>
```

### Schritt 2 – Docker Desktop starten

Docker Desktop öffnen und warten bis der Daemon läuft. Prüfen mit:

```bash
docker info
```

### Schritt 3 – `site_url` setzen

In `supabase/config.toml` die URL deiner Next.js App eintragen (Zeile `site_url`):

```toml
site_url = "http://localhost:3000"
```

### Schritt 4 – Setup mit App-Namen starten

```powershell
# PowerShell (Windows – direkt im VS Code Terminal)
.\scripts\setup.ps1 -App meine-shop-app
```

```bash
# Git Bash / macOS / Linux
./scripts/setup.sh --app meine-shop-app
```

Das Skript gibt aus, ob eine neue leere Instanz oder bestehende Daten geladen werden:

```
App: meine-shop-app
No existing data for 'meine-shop-app' → starting fresh.
```

### Schritt 5 – `.env.local` in die Next.js App kopieren

Das Skript erstellt `.env.local` im aktuellen Verzeichnis. Optional direkt in den App-Ordner schreiben:

```bash
./scripts/setup.sh --app meine-shop-app ../meine-nextjs-app
```

---

## Zwischen Apps wechseln (Schritt für Schritt)

### Aktuelle App stoppen

```powershell
# PowerShell (Windows – direkt im VS Code Terminal)
.\scripts\stop.ps1
```

```bash
# Git Bash / macOS / Linux
./scripts/stop.sh
```

Das Skript stoppt Supabase und entfernt alle verbleibenden Container zuverlässig.

### Andere App starten – Daten werden wiederhergestellt

```bash
./scripts/setup.sh --app andere-app
```

Ausgabe:

```
App: andere-app
Existing data found for 'andere-app' → resuming.
```

Alle Schemas, Tabellen und Datensätze der anderen App sind sofort wieder verfügbar.

### Alle gespeicherten App-Volumes anzeigen

```bash
docker volume ls --filter "name=supabase_db_"
```

Beispielausgabe:

```
DRIVER    VOLUME NAME
local     supabase_db_meine-shop-app
local     supabase_db_andere-app
local     supabase_db_test-projekt
```

---

## App-Daten zurücksetzen (Schritt für Schritt)

Falls du eine App mit frischen, leeren Daten neu starten möchtest:

```powershell
# PowerShell
.\scripts\setup.ps1 -App meine-shop-app -Reset
```

```bash
# Git Bash / macOS / Linux
./scripts/setup.sh --app meine-shop-app --reset
```

Das Skript:
1. Stoppt Supabase sauber
2. Löscht das Docker-Volume `supabase_db_meine-shop-app` unwiderruflich
3. Startet eine leere neue Instanz

> **Achtung:** `--reset` löscht alle lokalen Daten dieser App dauerhaft.

---

## Was `setup.sh` automatisch macht

- prüft Docker und Supabase CLI
- setzt `project_id` in `supabase/config.toml` auf den gewählten App-Namen
- prüft ob bereits ein Docker-Volume für diese App existiert und meldet Resuming oder Fresh Start
- sucht automatisch einen freien Port-Block
  - zuerst: `54321–54324`
  - dann: `54331–54334`, `54341–54344`, ...
- schreibt die Ports nach `.ports`
- patcht `supabase/config.toml` mit den gewählten Ports
- startet `supabase start`
- extrahiert API URL + Keys (kompatibel mit altem und neuem CLI-Ausgabeformat)
- erstellt `.env.local` (mit Backup als `.env.local.backup`, falls bereits vorhanden)

---

## Port-Übersicht

| Service | Standard-Port | URL | Beschreibung |
|---|---:|---|---|
| API | 54321 | http://127.0.0.1:54321 | REST/GraphQL Endpoint für die App |
| Database | 54322 | postgresql://localhost:54322 | Direkter PostgreSQL-Zugriff |
| Studio | 54323 | http://127.0.0.1:54323 | Supabase Studio UI |
| Inbucket | 54324 | http://127.0.0.1:54324 | Lokales Email-Testing |

> Hinweis: Wenn Standard-Ports belegt sind, wählt `setup.sh` automatisch andere Ports. Die gewählten Ports stehen in der Datei `.ports`.

---

## Mehrere Apps gleichzeitig

Du kannst mehrere lokale Supabase-Instanzen parallel betreiben. Dafür benötigst du mehrere Kopien dieses Repos. `setup.sh` wählt automatisch den nächsten freien 10er-Block:

| App | API | DB | Studio | Inbucket |
|---|---:|---:|---:|---:|
| App A | 54321 | 54322 | 54323 | 54324 |
| App B | 54331 | 54332 | 54333 | 54334 |

Du musst dafür nichts manuell konfigurieren. Jede Instanz nutzt ihre eigene `.ports`-Datei in ihrer eigenen Repo-Kopie.

---

## Migrations

```bash
# Neue Migration erstellen
supabase migration new <name>

# Lokale DB neu aufsetzen und Migrations + Seed ausführen
supabase db reset

# Migrationen auf Supabase Cloud anwenden
supabase db push
```

---

## Nützliche Befehle

| Befehl | Beschreibung |
|---|---|
| `./scripts/setup.sh --app <name>` | Startet Supabase für die genannte App (neu oder Daten wiederherstellen) |
| `./scripts/setup.sh --app <name> --reset` | Löscht App-Daten und startet leere Instanz |
| `./scripts/setup.sh --app <name> ../app` | Schreibt `.env.local` direkt in den angegebenen App-Ordner |
| `./scripts/setup.sh` | Nutzt den App-Namen aus `config.toml` (wie bisher) |
| `./scripts/status.sh` | Zeigt Portzuordnung und aktuellen Instanzstatus/Keys |
| `./scripts/stop.sh` | Stoppt die lokale Supabase-Instanz und bereinigt alle Container |
| `./scripts/validate.sh` | Führt Syntaxchecks, Unittests und Coverage-Checks aus |
| `docker volume ls --filter "name=supabase_db_"` | Zeigt alle gespeicherten App-Volumes |
| `supabase status` | Zeigt laufende lokale Services + Keys |
| `supabase migration new <name>` | Erstellt neue Migration |
| `supabase db reset` | Setzt lokale DB zurück und spielt Migrations/Seed ein |
| `supabase db push` | Schiebt Migrations in verbundenes Cloud-Projekt |

---

## Unittests & Validierung

Dieses Repository enthält ausführliche Bash-Unittests für `setup.sh`, `stop.sh` und `status.sh`, inklusive Fehlerpfaden.

```bash
# Alles (Syntax + Tests + Coverage)
./scripts/validate.sh

# Nur Tests + Coverage
./tests/run_all.sh
```

Die Coverage wird als marker-basierte Codeabdeckung geprüft (`tests/coverage_markers.txt`) und muss im CI-Check auf **100%** liegen.

---

## Wechsel zu Supabase Cloud

1. Supabase Cloud Projekt erstellen
2. Aus dem Cloud-Projekt kopieren:
   - Project URL
   - anon key
   - service_role key
3. In der App `.env.local` ersetzen:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
   - `SUPABASE_SERVICE_ROLE_KEY`
4. Dieselben Werte in Vercel als Environment Variables setzen (Preview + Production)

---

## Troubleshooting

### Docker läuft nicht

- Docker Desktop starten
- Prüfen mit: `docker info`

### `supabase start` schlägt fehl mit Container-Konflikt

Verwaiste Container von einem unvollständigen Stop bereinigen:

```bash
./scripts/stop.sh
```

`stop.sh` erzwingt danach automatisch die Entfernung aller verbleibenden Container für die aktive App.

### Alle Port-Blöcke belegt

- Selten, aber bei vielen parallelen Instanzen möglich
- Nicht benötigte Instanzen stoppen: `./scripts/stop.sh`
- Danach `./scripts/setup.sh` erneut starten

### Keys stimmen nicht / Auth funktioniert nicht lokal

- `./scripts/status.sh` ausführen und Werte prüfen
- `.env.local` neu erzeugen mit `./scripts/setup.sh --app <name>`

### `.ports`-Datei fehlt

- `./scripts/setup.sh --app <name>` erneut ausführen, damit Ports und Config neu gesetzt werden

### Analytics-Warnung auf Windows

```
WARNING: Analytics on Windows requires Docker daemon exposed on tcp://localhost:2375.
```

Dies ist eine bekannte Einschränkung auf Windows. Supabase startet trotzdem vollständig. Die Warnung kann ignoriert werden. Optional kann der Docker-Daemon unter **Docker Desktop → Settings → General → "Expose daemon on tcp://localhost:2375 without TLS"** freigegeben werden (nur für lokale Entwicklung).
