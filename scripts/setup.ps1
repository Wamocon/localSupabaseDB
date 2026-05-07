param(
    [string]$App = "",
    [switch]$Reset
)

$ErrorActionPreference = "Continue"
$RepoRoot    = Split-Path -Parent $PSScriptRoot
$ConfigFile  = Join-Path $RepoRoot "supabase\config.toml"
$TemplateFile= Join-Path $RepoRoot "supabase\config.toml.template"
$EnvFile     = Join-Path $RepoRoot ".env.local"
$EnvBackup   = Join-Path $RepoRoot ".env.local.backup"

# Lokale Supabase-CLI (aus npm install) bevorzugen, um Konflikte mit globalem Install zu vermeiden
$localBin = Join-Path $RepoRoot "node_modules\.bin"
if (Test-Path $localBin) { $env:PATH = "$localBin;$env:PATH" }

function Write-Info($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host $msg -ForegroundColor Red; exit 1 }

# --- config.toml aus Template erstellen wenn nicht vorhanden ---
if (-not (Test-Path $ConfigFile)) {
    if (-not (Test-Path $TemplateFile)) {
        Write-Err "Weder config.toml noch config.toml.template gefunden. Repository beschaedigt?"
    }
    Copy-Item $TemplateFile $ConfigFile
    Write-Info "config.toml aus Template erstellt."
}

$SupabaseCmd = $null
function Invoke-Supabase {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Args
    )
    if (-not $SupabaseCmd) {
        Write-Err "Supabase CLI nicht initialisiert."
    }
    & $SupabaseCmd @Args
}

# --- Prerequisites ---
Write-Info "Checking prerequisites..."

$dockerPs = docker ps 2>&1
if ($LASTEXITCODE -ne 0) { Write-Err "Docker laeuft nicht. Bitte Docker Desktop starten." }

if (Get-Command supabase -ErrorAction SilentlyContinue) {
    $SupabaseCmd = "supabase"
} else {
    $localSupabase = Join-Path $RepoRoot "node_modules\.bin\supabase.cmd"
    if (Test-Path $localSupabase) {
        $SupabaseCmd = $localSupabase
        Write-Info "Nutze lokale Supabase CLI aus node_modules."
    }
}

if (-not $SupabaseCmd) {
    Write-Err "Supabase CLI nicht gefunden. Installiere sie global oder lokal mit 'npm install'. Siehe: https://supabase.com/docs/guides/cli"
}

# --- App-Name / project_id ---
if ($App -ne "") {
    $sanitized = $App.ToLower() -replace '[^a-z0-9-]','-' -replace '-+','-' -replace '^-|-$',''
    if ($sanitized.Length -gt 40) { $sanitized = $sanitized.Substring(0, 40) }
    if ($sanitized -eq "") { Write-Err "Ungueltiger App-Name: '$App'" }
    $App = $sanitized
    (Get-Content $ConfigFile) -replace '^project_id = ".*"', "project_id = `"$App`"" | Set-Content $ConfigFile
    Write-Info "App: $App"
} else {
    $m = Select-String -Path $ConfigFile -Pattern '^project_id = "(.*)"'
    $App = $m.Matches[0].Groups[1].Value
    Write-Info "App: $App (aus config.toml)"
}

# --- Volume-Check ---
$volName   = "supabase_db_$App"
$volExists = (docker volume ls --format "{{.Name}}" 2>$null) -contains $volName

if ($Reset) {
    Write-Warn "Daten werden zurueckgesetzt fuer '$App'..."
    Invoke-Supabase stop --no-backup 2>&1 | Out-Null
    docker volume rm $volName 2>&1 | Out-Null
    Write-Info "Zurueckgesetzt."
    $volExists = $false
}

if ($volExists) {
    Write-Info "Bestehende Daten gefunden fuer '$App' -> wird fortgesetzt."
} else {
    Write-Info "Keine Daten vorhanden fuer '$App' -> neue leere Instanz wird gestartet."
}

# --- Supabase starten ---
Write-Info "Starte Supabase..."
$startOutput = Invoke-Supabase start 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn "supabase start meldet Fehler. Pruefe Status..."
    $startOutput = Invoke-Supabase status 2>&1
}

# --- Keys parsen ---
# Supabase CLI nutzt Unicode-Box-Zeichen als Trennzeichen. Diese werden je nach
# PowerShell-Codepage unterschiedlich dargestellt. Daher matchen wir direkt auf
# die Wert-Muster, unabhaengig vom Trennzeichen.
function Get-LineContaining($lines, $label) {
    return $lines | Where-Object { $_ -is [string] -and $_ -match $label } | Select-Object -Last 1
}
function Get-FirstMatch($line, $pattern) {
    if ($line -match $pattern) { return $Matches[1] }
    return $null
}

$allOutput = $startOutput

# API URL: sucht http(s)://IP:Port auf der Zeile mit "Project URL" oder "API URL"
$urlLine = Get-LineContaining $allOutput 'Project URL|API URL'
$apiUrl  = Get-FirstMatch $urlLine '(https?://[\d\.]+:\d+)'

# Anon Key: neue Format "sb_publishable_..." oder altes "eyJ..."
$anonLine = Get-LineContaining $allOutput 'Publishable|anon key'
$anonKey  = Get-FirstMatch $anonLine '(sb_publishable_\S+|eyJ\S+)'

# Service Role Key: neue Format "sb_secret_..." oder altes "eyJ..."
# "Secret Key" ist der S3-Key, "Secret" allein ist der Auth-Key
$secretLine = Get-LineContaining $allOutput '(?<!\w)Secret(?!\s+Key)'
$serviceKey = Get-FirstMatch $secretLine '(sb_secret_\S+|eyJ\S+)'

# Fallback: supabase status separat abfragen
if (-not $anonKey -or -not $serviceKey) {
    Write-Warn "Keys nicht gefunden. Lese supabase status..."
    $statusOut = Invoke-Supabase status 2>&1
    if (-not $urlLine)    { $urlLine    = Get-LineContaining $statusOut 'Project URL|API URL' }
    if (-not $apiUrl)     { $apiUrl     = Get-FirstMatch $urlLine '(https?://[\d\.]+:\d+)' }
    if (-not $anonKey)    { $anonKey    = Get-FirstMatch (Get-LineContaining $statusOut 'Publishable|anon key') '(sb_publishable_\S+|eyJ\S+)' }
    if (-not $serviceKey) { $serviceKey = Get-FirstMatch (Get-LineContaining $statusOut '(?<!\w)Secret(?!\s+Key)') '(sb_secret_\S+|eyJ\S+)' }
}

if (-not $apiUrl)     { $apiUrl = "http://127.0.0.1:54321" }
if (-not $anonKey)    { Write-Err "Anon Key konnte nicht ermittelt werden. Bitte 'supabase status' manuell pruefen." }
if (-not $serviceKey) { Write-Err "Service Role Key konnte nicht ermittelt werden. Bitte 'supabase status' manuell pruefen." }

# --- .env.local schreiben ---
if (Test-Path $EnvFile) {
    Copy-Item $EnvFile $EnvBackup -Force
    Write-Warn "Vorhandene .env.local gesichert als .env.local.backup"
}

$envContent  = "# Generated by scripts/setup.ps1`r`n"
$envContent += "NEXT_PUBLIC_SUPABASE_URL=$apiUrl`r`n"
$envContent += "NEXT_PUBLIC_SUPABASE_ANON_KEY=$anonKey`r`n"
$envContent += "SUPABASE_SERVICE_ROLE_KEY=$serviceKey`r`n"
[System.IO.File]::WriteAllText($EnvFile, $envContent, [System.Text.UTF8Encoding]::new($false))

Write-Info "Erstellt: $EnvFile"

# --- DB URL ableiten ---
$dbPort = 54322
if ($apiUrl -match ':(\d+)') { $dbPort = [int]$Matches[1] + 1 }
$dbUrl = "postgresql://postgres:postgres@127.0.0.1:$dbPort/postgres"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  App:              $App" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  NEXT_PUBLIC_SUPABASE_URL"
Write-Host "  $apiUrl" -ForegroundColor Yellow
Write-Host ""
Write-Host "  NEXT_PUBLIC_SUPABASE_ANON_KEY"
Write-Host "  $anonKey" -ForegroundColor Yellow
Write-Host ""
Write-Host "  SUPABASE_SERVICE_ROLE_KEY"
Write-Host "  $serviceKey" -ForegroundColor Yellow
Write-Host ""
Write-Host "  DATABASE_URL (direkt)"
Write-Host "  $dbUrl" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Studio:  http://127.0.0.1:54323"
Write-Host "  Mailpit: http://127.0.0.1:54324"
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Naechste Schritte:"
Write-Host "1) 'site_url' in supabase/config.toml auf deine Next.js-URL setzen."
Write-Host "2) .env.local in deine Next.js-App kopieren."
