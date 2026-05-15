param(
    [string]$App = "",
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

# App-Name normalisieren wenn angegeben
if ($App -ne "") {
    $App = $App.ToLower() -replace '[^a-z0-9-]','-' -replace '-+','-' -replace '^-|-$',''
    Write-Host ""
    Write-Host "App-spezifischer Purge: nur '$App' wird geloescht." -ForegroundColor Yellow
}

# Sicherheitsabfrage
if (-not $Force) {
    Write-Host ""
    if ($App -ne "") {
        Write-Host "ACHTUNG: Docker-Volume 'supabase_db_$App' (alle Daten von '$App') wird" -ForegroundColor Red
        Write-Host "         unwiderruflich geloescht." -ForegroundColor Red
    } else {
        Write-Host "ACHTUNG: Dieser Befehl stoppt alle lokalen Supabase-Instanzen und" -ForegroundColor Red
        Write-Host "         loescht alle zugehoerigen Docker-Volumes (alle App-Daten)." -ForegroundColor Red
    }
    Write-Host ""
    $confirm = Read-Host "Wirklich loeschen? (yes eingeben zum Bestaetigen)"
    if ($confirm -ne "yes") {
        Write-Warn "Abgebrochen."
        exit 0
    }
}

# --- Laufende Supabase-Instanz stoppen ---
Write-Info "Stoppe laufende Supabase-Instanz..."
supabase stop --no-backup 2>&1 | Out-Null

# --- Container entfernen (app-spezifisch oder alle) ---
Write-Info "Entferne verbleibende Container..."
if ($App -ne "") {
    $containers = docker ps -aq --filter "name=supabase_" --filter "label=com.supabase.cli.project=$App" 2>$null
    # Auch den DB-Container direkt ansprechen (hat kein project-Label)
    $dbContainer = docker ps -aq --filter "name=supabase_db_$App" 2>$null
    $containers = @($containers) + @($dbContainer) | Where-Object { $_ -ne "" } | Select-Object -Unique
} else {
    $containers = docker ps -aq --filter "name=supabase_" 2>$null
}
if ($containers) {
    docker rm -f $containers 2>&1 | Out-Null
    Write-Warn "Container entfernt."
}

# --- Volumes löschen (app-spezifisch oder alle) ---
Write-Info "Suche Supabase-Volumes..."
if ($App -ne "") {
    $volumes = docker volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -eq "supabase_db_$App" -or $_ -match "^supabase_.*_${App}$" }
} else {
    $volumes = docker volume ls --format "{{.Name}}" 2>$null | Where-Object { $_ -match "^supabase_" }
}

if (-not $volumes) {
    Write-Warn "Keine passenden Supabase-Volumes gefunden."
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

# --- config.toml loeschen (nur bei globalem Purge, nicht app-spezifisch) ---
if ($App -eq "" -and (Test-Path $ConfigFile)) {
    Remove-Item $ConfigFile
    Write-Info "config.toml geloescht (wird beim naechsten Start aus Template neu erstellt)."
}

Write-Host ""
if ($App -ne "") {
    Write-Info "Bereinigung von '$App' abgeschlossen."
    Write-Host "Neuen Start mit:  .\scripts\setup.ps1 -App $App"
} else {
    Write-Info "Bereinigung abgeschlossen. Alle Supabase-Daten wurden geloescht."
    Write-Host "Neuen Start mit:  .\scripts\setup.ps1 -App <name>"
}
