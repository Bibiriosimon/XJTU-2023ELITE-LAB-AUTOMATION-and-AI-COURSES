$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$frontendDir = Join-Path $root "frontend"
$backendDir = Join-Path $root "backend"
$venvPython = Join-Path $root ".venv\Scripts\python.exe"
$gtkBin = "C:\Program Files\GTK3-Runtime Win64\bin"

if (-not (Test-Path $venvPython)) {
    throw "Python virtual environment not found: $venvPython"
}

if (-not (Test-Path $gtkBin)) {
    throw "GTK runtime not found: $gtkBin"
}

$backendPort = 8796
$frontendPort = 6002

function Stop-PortProcess {
    param([int]$Port)

    $conn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($conn) {
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

Stop-PortProcess -Port $backendPort
Stop-PortProcess -Port $frontendPort

$backendStdout = Join-Path $backendDir "backend-dev.log"
$backendStderr = Join-Path $backendDir "backend-dev.err.log"
$frontendStdout = Join-Path $frontendDir "frontend-dev.log"
$frontendStderr = Join-Path $frontendDir "frontend-dev.err.log"
$pidFile = Join-Path $root ".autofigure-pids.json"

Remove-Item $backendStdout, $backendStderr, $frontendStdout, $frontendStderr -ErrorAction SilentlyContinue

$backendCommand = "`$env:Path = '$gtkBin;' + `$env:Path; & '$venvPython' 'app.py'"
$backend = Start-Process -FilePath "powershell.exe" `
    -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $backendCommand `
    -WorkingDirectory $backendDir `
    -RedirectStandardOutput $backendStdout `
    -RedirectStandardError $backendStderr `
    -PassThru

$frontend = Start-Process -FilePath "npm.cmd" `
    -ArgumentList "run", "dev" `
    -WorkingDirectory $frontendDir `
    -RedirectStandardOutput $frontendStdout `
    -RedirectStandardError $frontendStderr `
    -PassThru

@{
    backend_pid = $backend.Id
    frontend_pid = $frontend.Id
    backend_port = $backendPort
    frontend_port = $frontendPort
} | ConvertTo-Json | Set-Content -Path $pidFile -Encoding UTF8

Write-Host "Backend PID: $($backend.Id)"
Write-Host "Frontend PID: $($frontend.Id)"
Write-Host "Backend: http://127.0.0.1:$backendPort/health"
Write-Host "Frontend: http://127.0.0.1:$frontendPort"
Write-Host "Backend log: $backendStdout"
Write-Host "Frontend log: $frontendStdout"
