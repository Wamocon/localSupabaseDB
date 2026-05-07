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

## Konzept (kurz erklärt)

- Dieses Repository startet lokal eine vollständige Supabase-Instanz per Docker + Supabase CLI.
- Das Setup ist kompatibel zu Supabase Cloud über dieselben Variablen:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`
- Jede App erhält eine eigene Kopie dieses Repos.
- Port-Philosophie:
  - Supabase lokal: 54321+ (54000er Bereich)
  - Next.js Apps lokal: 3000–3999

## Erstes Setup (Schritt für Schritt)

1. Repository klonen:

```bash
git clone https://github.com/<deine-org-oder-user>/<dein-repo-name>.git
cd <dein-repo-name>
```

2. Docker starten (Docker Desktop / Docker Engine muss laufen).

3. Setup-Skript ausführen:

```bash
./scripts/setup.sh
```

Optional: `.env.local` direkt in einer App schreiben:

```bash
./scripts/setup.sh ../meine-nextjs-app
```

### Was `setup.sh` automatisch macht

- prüft Docker und Supabase CLI
- sucht automatisch einen freien Port-Block
  - zuerst: `54321-54324`
  - dann: `54331-54334`, `54341-54344`, ...
- schreibt die Ports nach `.ports`
- patcht `supabase/config.toml` mit den gewählten Ports
- startet `supabase start`
- extrahiert API URL + Keys
- erstellt/überschreibt `.env.local` (mit Backup als `.env.local.backup`, falls vorhanden)

### Wo stehen die Keys?

- Im `setup.sh`-Output (aus `supabase start`)
- Zusätzlich über `./scripts/status.sh` (zeigt `supabase status`)

> Hinweis: `site_url` in `supabase/config.toml` ist absichtlich ein Platzhalter. Trage dort die URL deiner Next.js App ein (z. B. `http://localhost:3000` oder `http://localhost:3001`).

## Port-Übersicht

| Service | Standard-Port | URL | Beschreibung |
|---|---:|---|---|
| API | 54321 | http://127.0.0.1:54321 | REST/GraphQL Endpoint für die App |
| Database | 54322 | postgresql://localhost:54322 | Direkter PostgreSQL-Zugriff |
| Studio | 54323 | http://127.0.0.1:54323 | Supabase Studio UI |
| Inbucket | 54324 | http://127.0.0.1:54324 | Lokales Email-Testing |

> Hinweis: Wenn Standard-Ports belegt sind, wählt `setup.sh` automatisch andere Ports. Prüfe dann die Datei `.ports`.

## Mehrere Apps gleichzeitig

Du kannst mehrere lokale Supabase-Instanzen parallel nutzen. `setup.sh` wählt automatisch den nächsten freien 10er-Block.

Beispiel:

| App | API | DB | Studio | Inbucket |
|---|---:|---:|---:|---:|
| App A | 54321 | 54322 | 54323 | 54324 |
| App B | 54331 | 54332 | 54333 | 54334 |

Du musst dafür nichts manuell konfigurieren. Jede Instanz nutzt ihre eigene `.ports` Datei in ihrer eigenen Repo-Kopie.

## Migrations

```bash
# Neue Migration erstellen
supabase migration new <name>

# Lokale DB neu aufsetzen und Migrations + Seed ausführen
supabase db reset

# Migrationen auf Supabase Cloud anwenden
supabase db push
```

## Nützliche Befehle

| Befehl | Beschreibung |
|---|---|
| `./scripts/setup.sh` | Startet Supabase mit dynamischer Portwahl und erzeugt `.env.local` |
| `./scripts/setup.sh ../app` | Schreibt `.env.local` direkt in den angegebenen App-Ordner |
| `./scripts/status.sh` | Zeigt Portzuordnung und aktuellen Instanzstatus/Keys |
| `./scripts/stop.sh` | Stoppt die lokale Supabase-Instanz |
| `./scripts/validate.sh` | Führt Syntaxchecks, Unittests und Coverage-Checks aus |
| `supabase start` | Startet lokale Supabase-Services |
| `supabase stop` | Stoppt lokale Supabase-Services |
| `supabase status` | Zeigt laufende lokale Services + Keys |
| `supabase migration new <name>` | Erstellt neue Migration |
| `supabase db reset` | Setzt lokale DB zurück und spielt Migrations/Seed ein |
| `supabase db push` | Schiebt Migrations in verbundenes Cloud-Projekt |

## Unittests & Validierung

Dieses Repository enthält ausführliche Bash-Unittests für `setup.sh`, `stop.sh` und `status.sh`, inklusive Fehlerpfaden.

```bash
# Alles (Syntax + Tests + Coverage)
./scripts/validate.sh

# Nur Tests + Coverage
./tests/run_all.sh
```

Die Coverage wird als marker-basierte Codeabdeckung geprüft (`tests/coverage_markers.txt`) und muss im CI-Check auf **100%** liegen.

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

## Troubleshooting

### Docker läuft nicht

- Docker Desktop starten
- Prüfen mit: `docker info`

### Alle Port-Blöcke belegt

- Selten, aber bei vielen parallelen Instanzen möglich
- Nicht benötigte Instanzen stoppen: `./scripts/stop.sh`
- Danach `./scripts/setup.sh` erneut starten

### `supabase start` schlägt fehl

- `supabase --version` prüfen
- Docker-Status prüfen
- Logs/Status prüfen: `supabase status`

### Keys stimmen nicht / Auth funktioniert nicht lokal

- `./scripts/status.sh` ausführen und Werte prüfen
- `.env.local` neu erzeugen mit `./scripts/setup.sh`

### `.ports` Datei fehlt

- `./scripts/setup.sh` erneut ausführen, damit Ports und Config neu gesetzt werden
