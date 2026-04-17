$ErrorActionPreference = "SilentlyContinue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$pidFile = Join-Path $root ".autofigure-pids.json"

if (Test-Path $pidFile) {
    $pids = Get-Content $pidFile | ConvertFrom-Json
    if ($pids.backend_pid) {
        Stop-Process -Id $pids.backend_pid -Force
    }
    if ($pids.frontend_pid) {
        Stop-Process -Id $pids.frontend_pid -Force
    }
    Remove-Item $pidFile -Force
}

foreach ($port in 8796, 6002) {
    $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($conn) {
        Stop-Process -Id $conn.OwningProcess -Force
    }
}

Write-Host "AutoFigure processes stopped."
