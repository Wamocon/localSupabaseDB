$RepoRoot   = Split-Path -Parent $PSScriptRoot
$ConfigFile = Join-Path $RepoRoot "supabase\config.toml"

function Write-Info($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }

# Aktuellen App-Namen aus config.toml lesen
$match     = Select-String -Path $ConfigFile -Pattern '^project_id = "(.*)"'
$projectId = $match.Matches[0].Groups[1].Value

Write-Info "Stopping Supabase ($projectId)..."
supabase stop 2>&1 | ForEach-Object { Write-Host $_ }

# Verbleibende Container entfernen (verhindert Konflikte beim nächsten Start)
$containers = docker ps -aq --filter "name=$projectId" 2>$null
if ($containers) {
    docker rm -f $containers 2>&1 | Out-Null
    Write-Warn "Verbleibende Container entfernt."
}

Write-Info "Gestoppt."
