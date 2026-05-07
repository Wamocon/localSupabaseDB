param(
    [switch]$Force
)

$ErrorActionPreference = "Continue"
$RepoRoot   = Split-Path -Parent $PSScriptRoot
$ConfigFile = Join-Path $RepoRoot "supabase\config.toml"

# Lokale Supabase-CLI bevorzugen
$localBin = Join-Path $RepoRoot "node_modules\.bin"
if (Test-Path $localBin) { $env:PATH = "$localBin;$env:PATH" }

function Write-Info($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host $msg -ForegroundColor Red; exit 1 }

# Sicherheitsabfrage
if (-not $Force) {
    Write-Host ""
    Write-Host "ACHTUNG: Dieser Befehl stoppt alle lokalen Supabase-Instanzen und" -ForegroundColor Red
    Write-Host "         loescht alle zugehoerigen Docker-Volumes (alle App-Daten)." -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "Wirklich alles loeschen? (yes eingeben zum Bestaetigen)"
    if ($confirm -ne "yes") {
        Write-Warn "Abgebrochen."
        exit 0
    }
}

# --- Laufende Supabase-Instanz stoppen ---
Write-Info "Stoppe laufende Supabase-Instanz..."
supabase stop --no-backup 2>&1 | Out-Null

# --- Alle Container mit Supabase-Projektbezug entfernen ---
Write-Info "Entferne verbleibende Container..."
$containers = docker ps -aq --filter "name=supabase_" 2>$null
if ($containers) {
    docker rm -f $containers 2>&1 | Out-Null
    Write-Warn "Container entfernt."
}

# --- Alle supabase_db_* Volumes auflisten und loeschen ---
Write-Info "Suche Supabase-Volumes..."
$volumes = docker volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -match "^supabase_" }

if (-not $volumes) {
    Write-Warn "Keine Supabase-Volumes gefunden."
} else {
    Write-Host ""
    Write-Host "Folgende Volumes werden geloescht:" -ForegroundColor Yellow
    $volumes | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    foreach ($vol in $volumes) {
        docker volume rm $vol 2>&1 | Out-Null
        Write-Warn "Geloescht: $vol"
    }
}

# --- config.toml loeschen (wird beim naechsten Start frisch aus Template kopiert) ---
if (Test-Path $ConfigFile) {
    Remove-Item $ConfigFile
    Write-Info "config.toml geloescht (wird beim naechsten Start aus Template neu erstellt)."
}

Write-Host ""
Write-Info "Bereinigung abgeschlossen. Alle Supabase-Daten wurden geloescht."
Write-Host "Neuen Start mit:  .\scripts\setup.ps1 -App <name>"
