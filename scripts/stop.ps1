param(
    [string]$App = ""
)

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$ConfigFile = Join-Path $RepoRoot "supabase\config.toml"

# Lokale Supabase-CLI bevorzugen
$localBin = Join-Path $RepoRoot "node_modules\.bin"
if (Test-Path $localBin) { $env:PATH = "$localBin;$env:PATH" }

# UTF-8 Ausgabe erzwingen (verhindert kryptische Spinner-Zeichen der Supabase CLI)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

function Write-Info($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }

# App-Namen bestimmen: Parameter hat Vorrang vor config.toml
if ($App -ne "") {
    $sanitized = $App.ToLower() -replace '[^a-z0-9-]','-' -replace '-+','-' -replace '^-|-$',''
    if ($sanitized -eq "") { Write-Host "Ungültiger App-Name: '$App'" -ForegroundColor Red; exit 1 }
    $projectId = $sanitized
    # project_id in config.toml auf die zu stoppende App setzen
    (Get-Content $ConfigFile) -replace '^project_id = ".*"', "project_id = `"$projectId`"" | Set-Content $ConfigFile
} else {
    $match     = Select-String -Path $ConfigFile -Pattern '^project_id = "(.*)"'
    $projectId = $match.Matches[0].Groups[1].Value
}

Write-Info "Stoppe Supabase ($projectId)..."
supabase stop 2>&1 | Out-Null

# Verbleibende Container entfernen (verhindert Konflikte beim nächsten Start)
$containers = docker ps -aq --filter "name=$projectId" 2>$null
if ($containers) {
    docker rm -f $containers 2>&1 | Out-Null
    Write-Warn "Verbleibende Container entfernt."
}

Write-Info "Gestoppt."
