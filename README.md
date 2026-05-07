# localSupabaseDB

Template-Repository für lokale Supabase-Entwicklungsumgebungen. Jede Next.js-Web-App bekommt eine eigene Kopie dieses Repos, damit lokal ohne Supabase-Cloud-Projekt entwickelt werden kann.

---

## Schnellstart

> Voraussetzung: [Docker Desktop](https://www.docker.com/products/docker-desktop/) läuft, `npm install` wurde einmalig ausgeführt.

### Starten
```powershell
.\scripts\setup.ps1 -App <app-name>
```
Erstellt die Datenbank (beim ersten Mal) oder setzt sie fort. Gibt URL + Keys aus.

### Stoppen
```powershell
.\scripts\stop.ps1
```
Stoppt alle Container. Daten bleiben erhalten.

### Daten dieser App löschen und neu starten
```powershell
.\scripts\setup.ps1 -App <app-name> -Reset
```

### Alles löschen (alle Apps)
```powershell
.\scripts\purge.ps1
```

---

## Inhaltsverzeichnis

1. [Was ist das hier?](#was-ist-das-hier)
2. [Voraussetzungen](#voraussetzungen)
3. [Konzept: Wie funktioniert das?](#konzept-wie-funktioniert-das)
4. [Erstes Setup – Schritt für Schritt](#erstes-setup--schritt-für-schritt)
5. [App starten und stoppen](#app-starten-und-stoppen)
6. [Zwischen Apps wechseln](#zwischen-apps-wechseln)
7. [App-Daten zurücksetzen](#app-daten-zurücksetzen)
8. [Alles löschen (Purge)](#alles-löschen-purge)
9. [Was wird beim Start angezeigt?](#was-wird-beim-start-angezeigt)
10. [Migrations – Datenbankstruktur verwalten](#migrations--datenbankstruktur-verwalten)
11. [Alle Befehle im Überblick](#alle-befehle-im-überblick)
12. [Wechsel zu Supabase Cloud](#wechsel-zu-supabase-cloud)
13. [Unittests & CI](#unittests--ci)
14. [Troubleshooting](#troubleshooting)

---

## Was ist das hier?

Dieses Repository startet eine **vollständige Supabase-Datenbank lokal auf deinem Rechner** – ohne dass du ein Konto bei Supabase oder eine Internetverbindung brauchst. Die Daten liegen komplett auf deinem Rechner in einem Docker-Volume.

**Was ist Supabase?**  
Supabase ist ein Open-Source-Backend-as-a-Service: Es liefert dir eine PostgreSQL-Datenbank, Authentifizierung, Storage und mehr. Normalerweise nutzt man es als Cloud-Dienst. Mit diesem Template läuft es lokal.

**Was ist Docker?**  
Docker ist eine Software, die Programme in isolierten Containern ausführt. Supabase besteht aus mehreren Diensten (Datenbank, API, Studio-UI usw.) – Docker startet all diese Dienste auf deinem Rechner, ohne dass du sie einzeln installieren musst.

**Was ist ein Docker-Volume?**  
Ein Volume ist ein persistenter Speicherbereich auf deiner Festplatte, den Docker verwaltet. Dort speichert Supabase alle deine Tabellen, Schemas und Daten. Wenn du den Docker-Container stoppst, bleiben die Daten im Volume erhalten und werden beim nächsten Start wiederhergestellt.

---

## Voraussetzungen

Die folgenden Tools müssen **einmalig pro Entwickler-Rechner** installiert werden. Danach funktionieren sie für alle deine Apps.

### 1) Docker Desktop

Docker Desktop ist die Anwendung, die alle Supabase-Dienste als Container auf deinem Rechner startet.

- **Windows:** https://www.docker.com/products/docker-desktop/ → Installer herunterladen und ausführen. Beim ersten Start wird WSL2 (Windows Subsystem for Linux) aktiviert – das ist normal.
- **macOS:** Installer von der gleichen Seite, dann Docker Desktop öffnen.
- **Linux:** Docker Engine gemäß offizieller Anleitung installieren.

> Nach der Installation Docker Desktop starten und warten, bis in der Taskleiste das Docker-Symbol erscheint und der Status „Running" zeigt.

### 2) Supabase CLI

Die Supabase CLI ist ein Befehlszeilenprogramm, das die lokalen Supabase-Container startet und verwaltet. Die korrekte Version ist bereits in der `package.json` dieses Repos festgelegt.

```powershell
# Windows PowerShell / macOS / Linux – im Repo-Ordner ausführen
npm install
```

Das reicht. Die Skripte (`setup.ps1`, `stop.ps1` usw.) verwenden automatisch die lokale Version aus `node_modules/.bin/` – kein Konflikt mit einer eventuell global installierten Version.

> **Achtung:** Führe **nicht** `npm install supabase` oder `npm install -g supabase` aus – das installiert eine andere (möglicherweise inkompatible) Version separat und verursacht genau die Versions-Konflikte, die damit vermieden werden sollen.

Manuell prüfen (nach `npm install`):
```powershell
npx supabase --version
```

### 3) Node.js

- Node.js >= 18 (wird für npm benötigt)
- Download: https://nodejs.org

### 4) Git

- Git für Windows: https://git-scm.com/download/win
- macOS/Linux: meist vorinstalliert

---

> **Windows-Hinweis:** Alle Befehle in dieser Anleitung funktionieren direkt im **VS Code Terminal (PowerShell)**. Du musst kein Git Bash oder WSL öffnen.

> **Port-Philosophie:** Supabase nutzt Ports ab **54321** (54000er Bereich). Deine Next.js-Apps nutzen Ports **3000–3999**. Die Bereiche überschneiden sich nie.

---

## Konzept: Wie funktioniert das?

### Jede App bekommt einen eigenen Namen

Wenn du `setup.ps1 -App meine-app` ausführst, passiert folgendes:

1. Das Skript prüft ob `supabase/config.toml` existiert. Falls nicht (z.B. direkt nach `git clone`), wird sie automatisch aus `supabase/config.toml.template` kopiert.
2. Der Name `meine-app` wird als `project_id` in `supabase/config.toml` gesetzt.
2. Supabase benennt alle Docker-Container und Volumes nach diesem Namen:
   - Container: `supabase_db_meine-app`, `supabase_api_meine-app`, ...
   - Volume: `supabase_db_meine-app` ← **hier liegen deine Daten**
3. Beim nächsten Start mit demselben Namen werden genau diese Daten wieder geladen.

### Daten bleiben beim Stoppen erhalten

```
┌─────────────────────────────────────────────────────┐
│  Docker Volume: supabase_db_meine-app               │
│  ┌─────────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Tabellen   │  │ Schemas  │  │  Datensätze   │  │
│  └─────────────┘  └──────────┘  └───────────────┘  │
│                                                     │
│  → bleibt erhalten wenn Container gestoppt werden   │
└─────────────────────────────────────────────────────┘
```

### Mehrere Apps – komplett isoliert

Jede App hat ihr eigenes Volume. Sie teilen sich keine Daten:

```
supabase_db_shop-app       ← Daten von App "shop-app"
supabase_db_blog-app       ← Daten von App "blog-app"
supabase_db_test-projekt   ← Daten von App "test-projekt"
```

Du kannst jederzeit zwischen Apps wechseln – stoppen, andere App starten, fertig.

### Kompatibilität mit Supabase Cloud

Lokal und in der Cloud verwendest du **dieselben Umgebungsvariablen**:

| Variable | Bedeutung |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL des Supabase-API-Endpunkts |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Öffentlicher Schlüssel für Client-Zugriff |
| `SUPABASE_SERVICE_ROLE_KEY` | Geheimer Schlüssel für Server-seitigen Zugriff |

Lokal zeigen diese auf `http://127.0.0.1:54321`, in der Cloud auf dein Cloud-Projekt. Die App selbst muss nicht geändert werden.

---

## Erstes Setup – Schritt für Schritt

### Schritt 1 – Repository klonen und installieren

Öffne das VS Code Terminal (`Strg+ö`) und führe aus:

```powershell
git clone https://github.com/Wamocon/localSupabaseDB.git
cd localSupabaseDB
npm install
```

`npm install` installiert die Supabase CLI in der exakt richtigen Version lokal ins Repo. Die Skripte nutzen sie automatisch.

### Schritt 2 – Docker Desktop starten

Öffne Docker Desktop und warte, bis der Status „Engine running" zeigt. Ohne Docker funktioniert nichts.

Prüfen ob Docker läuft:
```powershell
docker ps
```
Wenn eine leere Tabelle erscheint (kein Fehler), läuft Docker.

### Schritt 3 – Supabase starten

```powershell
.\scripts\setup.ps1 -App meine-app
```

Ersetze `meine-app` durch den Namen deines Projekts, z.B. `shop`, `blog`, `schufacleaner`.

**Beim ersten Start** werden Docker-Images heruntergeladen (~1–2 GB). Das kann einige Minuten dauern. Danach startet Supabase sehr schnell.

> `site_url` ist standardmäßig auf `http://localhost:3000` gesetzt – das ist der Port deiner lokalen Next.js-App. Wenn du einen anderen Port nutzt, ändere es in `supabase/config.toml.template` und committe die Änderung.

### Schritt 4 – Variablen in die Next.js-App kopieren

Das Skript erstellt automatisch eine `.env.local`-Datei im Repository-Ordner. Kopiere sie in den Ordner deiner Next.js-App:

```powershell
# Beispiel: deine Next.js-App liegt in D:\IDEA\Projekt\meine-nextjs-app
Copy-Item .env.local ..\meine-nextjs-app\.env.local
```

Oder starte das Setup direkt mit dem Zielpfad (nur Bash):
```bash
./scripts/setup.sh --app meine-app ../meine-nextjs-app
```

---

## App starten und stoppen

### Starten

```powershell
# Windows PowerShell
.\scripts\setup.ps1 -App <app-name>

# Git Bash / macOS / Linux
./scripts/setup.sh --app <app-name>
```

### Stoppen

```powershell
# Windows PowerShell
.\scripts\stop.ps1

# Git Bash / macOS / Linux
./scripts/stop.sh
```

`stop.ps1` stoppt Supabase **und** entfernt danach automatisch alle verbleibenden Container. Das verhindert Fehler beim nächsten Start.

---

## Zwischen Apps wechseln

Das ist der typische Workflow wenn du an mehreren Projekten arbeitest:

**Schritt 1 – Aktuelle App stoppen:**
```powershell
.\scripts\stop.ps1
```

**Schritt 2 – Andere App starten:**
```powershell
.\scripts\setup.ps1 -App andere-app
```

Das Skript erkennt automatisch, ob Daten für diese App bereits vorhanden sind:

```
Bestehende Daten gefunden fuer 'andere-app' -> wird fortgesetzt.
```

oder bei einer neuen App:

```
Keine Daten vorhanden fuer 'andere-app' -> neue leere Instanz wird gestartet.
```

**Alle gespeicherten Apps anzeigen:**
```powershell
docker volume ls --filter "name=supabase_db_"
```

Beispielausgabe:
```
DRIVER    VOLUME NAME
local     supabase_db_shop-app
local     supabase_db_blog-app
local     supabase_db_schufacleaner
```

---

## App-Daten zurücksetzen

Wenn du für eine App **komplett neu starten** möchtest (alle Tabellen und Daten löschen):

```powershell
# Windows PowerShell
.\scripts\setup.ps1 -App meine-app -Reset

# Git Bash / macOS / Linux
./scripts/setup.sh --app meine-app --reset
```

Das Skript:
1. Stoppt Supabase sauber
2. Löscht das Docker-Volume `supabase_db_meine-app` **unwiderruflich**
3. Startet sofort eine leere neue Instanz

> **Achtung:** `-Reset` löscht alle lokalen Daten dieser App dauerhaft. Es gibt kein Backup.

---

## Alles löschen (Purge)

Mit `purge.ps1` kannst du **alle** lokalen Supabase-Instanzen stoppen und **alle** App-Volumes auf einmal löschen. Nützlich wenn du aufräumen oder komplett neu starten möchtest.

```powershell
# Mit Sicherheitsabfrage (empfohlen)
.\scripts\purge.ps1

# Ohne Abfrage (z.B. in Skripten)
.\scripts\purge.ps1 -Force
```

Was `purge.ps1` macht:
1. Fragt zur Sicherheit nach Bestätigung (Eingabe: `yes`)
2. Stoppt alle laufenden Supabase-Container
3. Entfernt alle verbleibenden Container
4. Löscht **alle** `supabase_*`-Volumes (alle App-Daten)
5. Löscht `supabase/config.toml` (wird beim nächsten Start automatisch neu aus dem Template erstellt)

> **Achtung:** Dieser Befehl löscht die Daten **aller** Apps auf einmal. Danach sind alle Volumes weg.

Nach einem Purge kannst du sofort wieder neu starten:
```powershell
.\scripts\setup.ps1 -App meine-app
```

---

## Was wird beim Start angezeigt?

Nach einem erfolgreichen Start zeigt das Skript alle wichtigen Verbindungsdaten:

```
============================================================
  App:              schufacleaner
============================================================
  NEXT_PUBLIC_SUPABASE_URL
  http://127.0.0.1:54321

  NEXT_PUBLIC_SUPABASE_ANON_KEY
  sb_publishable_ACJWlzQHlZj...

  SUPABASE_SERVICE_ROLE_KEY
  sb_secret_N7UND0Ugj...

  DATABASE_URL (direkt)
  postgresql://postgres:postgres@127.0.0.1:54322/postgres
============================================================
  Studio:  http://127.0.0.1:54323
  Mailpit: http://127.0.0.1:54324
============================================================
```

**Was bedeuten die einzelnen Werte?**

| Wert | Verwendung |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | In `.env.local` deiner Next.js-App – die App-URL für die Supabase-Verbindung |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | In `.env.local` – öffentlicher Schlüssel für Client-seitige Anfragen |
| `SUPABASE_SERVICE_ROLE_KEY` | In `.env.local` – geheimer Schlüssel für Server-seitige Anfragen (nie im Browser verwenden!) |
| `DATABASE_URL` | Direkte PostgreSQL-Verbindung, z.B. für DB-Tools wie TablePlus oder DBeaver |
| Studio | Browser-URL für die Supabase Studio UI – dort kannst du Tabellen und Daten grafisch verwalten |
| Mailpit | Browser-URL für das lokale E-Mail-Testing – alle Auth-E-Mails (z.B. Passwort-Reset) landen hier |

**Supabase Studio öffnen:**  
Öffne http://127.0.0.1:54323 im Browser. Dort siehst du die Datenbankstruktur, kannst SQL ausführen und Daten bearbeiten.

**Port-Übersicht:**

| Service | Port | URL |
|---|---:|---|
| API / REST | 54321 | http://127.0.0.1:54321 |
| Datenbank (PostgreSQL) | 54322 | postgresql://postgres:postgres@127.0.0.1:54322/postgres |
| Studio (UI) | 54323 | http://127.0.0.1:54323 |
| Mailpit (E-Mail) | 54324 | http://127.0.0.1:54324 |

> Wenn Standard-Ports belegt sind, wählt `setup.ps1` automatisch andere Ports (54331–54334, usw.). Die genutzten Ports stehen in der Datei `.ports`.

---

## Migrations – Datenbankstruktur verwalten

Migrations sind SQL-Dateien, die die Datenbankstruktur beschreiben (Tabellen, Spalten, Constraints usw.). Sie werden versioniert im Repository gespeichert.

### Neue Tabelle/Änderung erstellen

```powershell
supabase migration new tabellen-name
```

Das erstellt eine neue Datei in `supabase/migrations/`. Öffne sie und schreibe dein SQL rein:

```sql
-- supabase/migrations/20260507_create_products.sql
CREATE TABLE public.products (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL,
  price numeric NOT NULL,
  created_at timestamptz DEFAULT now()
);
```

### Migration auf lokale DB anwenden

```powershell
supabase db reset
```

Dieser Befehl setzt die lokale Datenbank zurück und spielt **alle** Migrations + die `seed.sql` neu ein. Nützlich wenn du die Struktur komplett neu aufbauen möchtest.

> Achtung: `db reset` löscht alle lokalen Daten und spielt die Migrations von Anfang an ein.

### Testdaten (Seed) eintragen

Trage deine Testdaten in `supabase/seed.sql` ein:

```sql
-- supabase/seed.sql
INSERT INTO public.products (name, price) VALUES
  ('Produkt A', 29.99),
  ('Produkt B', 49.99);
```

Diese Daten werden bei jedem `supabase db reset` automatisch eingespielt.

### Migration auf Supabase Cloud anwenden

```powershell
supabase db push
```

---

## Alle Befehle im Überblick

### Windows PowerShell (direkt im VS Code Terminal)

| Befehl | Beschreibung |
|---|---|
| `.\scripts\setup.ps1 -App <name>` | Supabase starten – neue App oder bestehende Daten laden |
| `.\scripts\setup.ps1 -App <name> -Reset` | App-Daten löschen und leere Instanz starten |
| `.\scripts\setup.ps1` | Letzten App-Namen aus `config.toml` verwenden |
| `.\scripts\stop.ps1` | Supabase stoppen und Container bereinigen |
| `.\scripts\purge.ps1` | Alles stoppen + alle App-Volumes löschen |
| `.\scripts\purge.ps1 -Force` | Wie purge, ohne Sicherheitsabfrage |

### Git Bash / macOS / Linux

| Befehl | Beschreibung |
|---|---|
| `./scripts/setup.sh --app <name>` | Supabase starten |
| `./scripts/setup.sh --app <name> --reset` | App-Daten löschen und neu starten |
| `./scripts/setup.sh --app <name> ../app` | `.env.local` direkt in App-Ordner schreiben |
| `./scripts/stop.sh` | Supabase stoppen |
| `./scripts/status.sh` | Status und Keys anzeigen |
| `./scripts/validate.sh` | Tests und Coverage ausführen |

### Docker-Befehle (PowerShell)

| Befehl | Beschreibung |
|---|---|
| `docker volume ls --filter "name=supabase_db_"` | Alle gespeicherten App-Volumes anzeigen |
| `docker ps` | Alle laufenden Container anzeigen |

### Supabase CLI

| Befehl | Beschreibung |
|---|---|
| `supabase status` | Laufende Instanz + Keys anzeigen |
| `supabase migration new <name>` | Neue Migration erstellen |
| `supabase db reset` | Lokale DB zurücksetzen (Migrations + Seed neu einspielen) |
| `supabase db push` | Migrations auf Cloud-Projekt anwenden |

---

## Wechsel zu Supabase Cloud

Wenn deine App produktionsreif ist, wechselst du von der lokalen Instanz auf Supabase Cloud:

1. Unter https://supabase.com ein neues Projekt erstellen
2. Im Cloud-Projekt unter **Settings → API** kopieren:
   - Project URL
   - `anon` public key
   - `service_role` secret key
3. Die Werte in der `.env.local` deiner App ersetzen:
   ```
   NEXT_PUBLIC_SUPABASE_URL=https://xxxxx.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJh...
   SUPABASE_SERVICE_ROLE_KEY=eyJh...
   ```
4. Migrations auf das Cloud-Projekt anwenden:
   ```powershell
   supabase db push
   ```
5. Bei Vercel/Netlify dieselben Werte als Environment Variables hinterlegen (Settings → Environment Variables)

---

## Unittests & CI

Dieses Repository enthält automatisierte Tests für alle Shell-Skripte. Sie werden bei jedem Push auf GitHub automatisch ausgeführt (GitHub Actions CI).

```powershell
# Alle Tests + Coverage lokal ausführen (Git Bash)
./scripts/validate.sh
```

Die Tests prüfen alle Codepfade der Skripte und müssen 100% Coverage erreichen.

---

## Troubleshooting

### Docker läuft nicht

**Fehlermeldung:** `Docker laeuft nicht. Bitte Docker Desktop starten.`

**Lösung:** Docker Desktop öffnen und warten bis der Status „Engine running" zeigt. Dann erneut versuchen.

Prüfen:
```powershell
docker ps
```

---

### `supabase start` schlägt fehl mit Container-Konflikt

**Fehlermeldung:** `failed to create docker container: Error response from daemon: Conflict. The container name "/supabase_xxx" is already in use`

Das passiert wenn Supabase beim letzten Mal nicht sauber gestoppt wurde und Container-Reste übrig blieben.

**Lösung:**
```powershell
.\scripts\stop.ps1
```

`stop.ps1` entfernt automatisch alle verbleibenden Container. Danach normal starten.

---

### Alle Port-Blöcke belegt

**Fehlermeldung:** `No free port block found from 54321 upwards.`

Das passiert wenn viele Instanzen gleichzeitig laufen.

**Lösung:** Nicht benötigte Instanzen stoppen:
```powershell
.\scripts\stop.ps1
```

---

### Keys werden nicht gefunden / `.env.local` ist leer

**Lösung:** `setup.ps1` erneut ausführen:
```powershell
.\scripts\setup.ps1 -App <name>
```

Das Skript liest die Keys direkt aus `supabase status` und schreibt `.env.local` neu.

---

### Analytics-Warnung auf Windows

```
WARNING: Analytics on Windows requires Docker daemon exposed on tcp://localhost:2375.
```

Das ist eine **harmlose Warnung**, kein Fehler. Supabase startet trotzdem vollständig und ist voll funktionsfähig. Die Warnung kann ignoriert werden.

Optional (nur für lokale Entwicklung, nicht produktiv): In Docker Desktop unter **Settings → General → „Expose daemon on tcp://localhost:2375 without TLS"** aktivieren.

---

### `.ports`-Datei fehlt

**Lösung:** Setup erneut ausführen:
```powershell
.\scripts\setup.ps1 -App <name>
```

Die `.ports`-Datei wird automatisch neu erstellt.


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

In `supabase/config.toml.template` ist `site_url` bereits auf `http://localhost:3000` voreingestellt – keinen manuellen Schritt erforderlich.

Nur wenn deine App auf einem anderen Port läuft, trage es dort ein und committe die Änderung:

```toml
site_url = "http://localhost:3001"
```

> `supabase/config.toml` ist gitignoriert. Gemeinsam genutzte Einstellungen gehören in `config.toml.template`.

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
- erstellt `supabase/config.toml` aus `config.toml.template` wenn sie nicht existiert (z.B. nach `git clone` oder `purge`)
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
