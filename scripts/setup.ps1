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
$PortsFile   = Join-Path $RepoRoot ".ports"

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

# --- Port-Zuweisung ---
function Test-PortFree([int]$Port) {
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return -not ($listeners | Where-Object Port -eq $Port)
}
function Find-FreePortBase([int]$Count = 4, [int]$Start = 54321) {
    for ($base = $Start; $base -lt 60000; $base += $Count) {
        $ok = $true
        for ($i = 0; $i -lt $Count; $i++) { if (-not (Test-PortFree ($base + $i))) { $ok = $false; break } }
        if ($ok) { return $base }
    }
    return $null
}

$portsMap = @{}
if (Test-Path $PortsFile) {
    try {
        $j = Get-Content $PortsFile -Raw | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) {
            $portsMap[$p.Name] = @{
                api       = $p.Value.api
                db        = $p.Value.db
                studio    = $p.Value.studio
                inbucket  = $p.Value.inbucket
                analytics = $p.Value.analytics
            }
        }
    } catch {}
}

if ($portsMap.ContainsKey($App)) {
    $portApi      = $portsMap[$App].api
    $portDb       = $portsMap[$App].db
    $portStudio   = $portsMap[$App].studio
    $portInbucket = $portsMap[$App].inbucket
    $portAnalytics = if ($portsMap[$App].analytics) { $portsMap[$App].analytics } else { $portsMap[$App].api + 4 }
    # Analytics-Feld nachtraegen falls es in aelteren Eintraegen fehlte
    if (-not $portsMap[$App].analytics) {
        $portsMap[$App].analytics = $portAnalytics
        $portsMap | ConvertTo-Json | Set-Content $PortsFile -Encoding UTF8
    }
    Write-Info "Ports fuer '$App': API=$portApi  DB=$portDb  Studio=$portStudio  Inbucket=$portInbucket  Analytics=$portAnalytics"
} else {
    $base = Find-FreePortBase -Count 5 -Start 54321
    if (-not $base) { Write-Err "Keine 5 freien aufeinanderfolgenden Ports gefunden." }
    $portApi = $base; $portDb = $base + 1; $portStudio = $base + 2; $portInbucket = $base + 3; $portAnalytics = $base + 4
    $portsMap[$App] = @{ api = $portApi; db = $portDb; studio = $portStudio; inbucket = $portInbucket; analytics = $portAnalytics }
    $portsMap | ConvertTo-Json | Set-Content $PortsFile -Encoding UTF8
    Write-Info "Neue Ports fuer '$App': API=$portApi  DB=$portDb  Studio=$portStudio  Inbucket=$portInbucket  Analytics=$portAnalytics"
}

# Sicherstellen dass [analytics] in config.toml vorhanden ist (Abwaertskompatibilitaet)
if (-not (Get-Content $ConfigFile | Select-String '^\[analytics\]')) {
    Add-Content $ConfigFile "`n[analytics]`n# Logflare analytics service port.`nport = 54327"
}

# Ports in config.toml aktualisieren
$currentSection = ""
$cfgLines = Get-Content $ConfigFile
$cfgLines = $cfgLines | ForEach-Object {
    $line = $_
    if ($line -match '^\[([^\]]+)\]') { $currentSection = $Matches[1] }
    if ($line -match '^port = \d+') {
        switch ($currentSection) {
            'api'       { $line = "port = $portApi" }
            'db'        { $line = "port = $portDb" }
            'studio'    { $line = "port = $portStudio" }
            'inbucket'  { $line = "port = $portInbucket" }
            'analytics' { $line = "port = $portAnalytics" }
        }
    }
    $line
}
$cfgLines | Set-Content $ConfigFile

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

# Hilfsfunktion: prueft ob Services laufen und Keys lieferbar sind
function Test-SupabaseRunning {
    $out = & $SupabaseCmd status -o env 2>&1
    return ($LASTEXITCODE -eq 0 -and ($out | Where-Object { $_ -match '^ANON_KEY=\S' }))
}

# Hilfsfunktion: erkennt PostgreSQL-Versions-Konflikt DIREKT aus dem Volume (vor jedem Start-Versuch)
function Test-PostgresVolumeMismatch([string]$AppName) {
    $volName = "supabase_db_$AppName"

    # Volume vorhanden? Wenn nicht -> kein Konflikt moeglich
    $null = docker volume inspect $volName 2>&1
    if ($LASTEXITCODE -ne 0) { return }

    # PG_VERSION direkt aus dem Volume lesen (kein sh -c, kein || )
    # 2>&1 noetig, sonst PS5.1 Fehler. Alpine-Pull-Meldungen werden weggefiltert.
    $volPgVerRaw = docker run --rm --volume "${volName}:/pgdata:ro" --network none alpine cat /pgdata/PG_VERSION 2>&1
    $volPgVer = ($volPgVerRaw | Where-Object { "$_".Trim() -match '^\d+$' } | Select-Object -Last 1)
    if (-not $volPgVer) { return }
    $volPgVer = $volPgVer.Trim()

    # Erwartete Version aus config.toml lesen (major_version = 15)
    $expectedPgVer = "15"
    $m = Select-String -Path $ConfigFile -Pattern 'major_version\s*=\s*(\d+)' -ErrorAction SilentlyContinue
    if ($m) { $expectedPgVer = $m.Matches[0].Groups[1].Value }

    if ($volPgVer -ne $expectedPgVer) {
        Write-Host ""
        Write-Host "======================================================" -ForegroundColor Red
        Write-Host "FATALER FEHLER: PostgreSQL-Versions-Konflikt!" -ForegroundColor Red
        Write-Host "======================================================" -ForegroundColor Red
        Write-Host "  Volume '$volName':           PG $volPgVer" -ForegroundColor Yellow
        Write-Host "  config.toml major_version:   PG $expectedPgVer" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Diese Kombination startet NIEMALS - kein Retry hilft." -ForegroundColor Red
        Write-Host ""
        Write-Host "OPTION 1: Daten sichern, dann Reset" -ForegroundColor Cyan
        Write-Host "  docker run --rm -v ${volName}:/var/lib/postgresql/data -e POSTGRES_PASSWORD=postgres -p 5434:5432 -d --name pgexport postgres:${volPgVer}" -ForegroundColor Gray
        Write-Host "  docker exec pgexport pg_dumpall -U postgres > ${AppName}_backup.sql" -ForegroundColor Gray
        Write-Host "  docker stop pgexport" -ForegroundColor Gray
        Write-Host "  .\scripts\setup.ps1 -App $AppName -Reset" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "OPTION 2: Reset ohne Backup" -ForegroundColor Cyan
        Write-Host "  .\scripts\setup.ps1 -App $AppName -Reset" -ForegroundColor Cyan
        Write-Host "======================================================" -ForegroundColor Red
        Write-Err "Abgebrochen wegen PostgreSQL-Versions-Konflikt."
    }
}

# === PG-Versions-Konflikt pruefen BEVOR irgendein Start-Versuch ===
Test-PostgresVolumeMismatch $App

# Versuch 1: Normaler Start
& $SupabaseCmd start 2>&1 | Tee-Object -Variable startOut | Out-Null
if ($LASTEXITCODE -ne 0) {

    # Manche CLI-Versionen geben non-zero zurueck, obwohl Services laufen (z.B. "already started")
    if (Test-SupabaseRunning) {
        Write-Info "Services laufen bereits (CLI-Exit-Code ignoriert)."
    } else {
        Write-Warn "Versuch 1 fehlgeschlagen. Starte Diagnose..."
        Write-Warn "--- supabase start Ausgabe ---"
        $startOut | Where-Object { $_ -is [string] } | Write-Host
        Write-Warn "--- Ende ---"

        # Versuch 2: Sauberer Stop + Neustart
        Write-Warn "Versuch 2: Stop + Neustart..."
        & $SupabaseCmd stop 2>&1 | Out-Null
        Start-Sleep -Seconds 5
        & $SupabaseCmd start 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -and -not (Test-SupabaseRunning)) {

            # Versuch 3: Docker-Container zwangsweise entfernen + Neustart
            Write-Warn "Versuch 3: Docker force-cleanup + Neustart..."
            $stuckContainers = @(docker ps -aq --filter "label=com.supabase.cli.project=$App" 2>$null)
            if ($stuckContainers.Count -gt 0) {
                Write-Warn "Entferne $($stuckContainers.Count) haengende Container..."
                docker rm -f $stuckContainers 2>$null | Out-Null
                Start-Sleep -Seconds 3
            }
            & $SupabaseCmd start 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0 -and -not (Test-SupabaseRunning)) {
                Write-Err "Supabase konnte nicht gestartet werden. Bitte 'docker ps -a' und 'supabase status' manuell pruefen."
            }
        }
    }
}

# --- Keys ermitteln ---
# Immer via 'supabase status -o env' - unabhaengig vom Start-Output-Format und Codepage.
# Helper-Funktionen fuer Text-Format-Fallback
function Get-LineContaining($lines, $label) {
    return $lines | Where-Object { $_ -is [string] -and $_ -match $label } | Select-Object -Last 1
}
function Get-FirstMatch($line, $pattern) {
    if ($line -match $pattern) { return $Matches[1] }
    return $null
}

$anonKey = $null; $serviceKey = $null; $apiUrl = $null

# Primaer: strukturiertes env-Format (stabil, unabhaengig von Box-Zeichen und Locale)
for ($attempt = 1; $attempt -le 3; $attempt++) {
    $envOut = & $SupabaseCmd status -o env 2>&1
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in $envOut) {
            if ($line -match '^ANON_KEY=(.+)$'            -and -not $anonKey)    { $anonKey    = $Matches[1].Trim().Trim('"') }
            if ($line -match '^SERVICE_ROLE_KEY=(.+)$'    -and -not $serviceKey) { $serviceKey = $Matches[1].Trim().Trim('"') }
            if ($line -match '^API_URL=(https?://\S+)$'   -and -not $apiUrl)     { $apiUrl     = $Matches[1].Trim().Trim('"') }
        }
    }
    if ($anonKey -and $serviceKey) { break }
    if ($attempt -lt 3) {
        Write-Warn "Keys noch nicht verfuegbar (Versuch $attempt/3). Warte 5 Sekunden..."
        Start-Sleep -Seconds 5
    }
}

# Fallback: Text-Format-Parsing (aeltere CLI-Versionen ohne -o env Support)
if (-not $anonKey -or -not $serviceKey) {
    Write-Warn "env-Format schlug fehl. Versuche Text-Parsing..."
    $statusOut = & $SupabaseCmd status 2>&1
    if (-not $apiUrl)     { $apiUrl     = Get-FirstMatch (Get-LineContaining $statusOut 'Project URL|API URL') '(https?://[\d\.]+:\d+)' }
    if (-not $anonKey)    { $anonKey    = Get-FirstMatch (Get-LineContaining $statusOut 'Publishable|anon key') '(sb_publishable_\S+|eyJ\S+)' }
    if (-not $serviceKey) { $serviceKey = Get-FirstMatch (Get-LineContaining $statusOut '(?<!\w)Secret(?!\s+Key)') '(sb_secret_\S+|eyJ\S+)' }
}

if (-not $apiUrl)     { $apiUrl = "http://127.0.0.1:$portApi" }
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
$dbPort = $portDb
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
Write-Host "  Studio:  http://127.0.0.1:$portStudio"
  Write-Host "  Mailpit: http://127.0.0.1:$portInbucket"
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Naechste Schritte:"
Write-Host "1) 'site_url' in supabase/config.toml auf deine Next.js-URL setzen."
Write-Host "2) .env.local in deine Next.js-App kopieren."
