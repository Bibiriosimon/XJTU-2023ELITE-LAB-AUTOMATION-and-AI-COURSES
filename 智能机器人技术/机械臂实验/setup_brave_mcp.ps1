$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir = Join-Path $Root ".venv"
$PythonExe = Join-Path $VenvDir "Scripts\python.exe"
$ConfigFile = Join-Path $Root "brave api.txt"

if (-not (Test-Path $ConfigFile)) {
    throw "Missing config file: $ConfigFile"
}

$PythonCmd = $null
if (Get-Command py -ErrorAction SilentlyContinue) {
    $PythonCmd = "py"
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $PythonCmd = "python"
} else {
    throw "Python was not found. Install Python 3 first."
}

if (-not (Test-Path $VenvDir)) {
    Write-Host "Creating virtual environment..."
    if ($PythonCmd -eq "py") {
        & py -3 -m venv $VenvDir
    } else {
        & python -m venv $VenvDir
    }
}

Write-Host "Installing MCP dependencies..."
& $PythonExe -m pip install --upgrade pip
& $PythonExe -m pip install mcp httpx

Write-Host ""
Write-Host "Setup finished."
Write-Host "Project root: $Root"
Write-Host "Next steps:"
Write-Host "1. Open Claude Code in this directory."
Write-Host "2. Run: claude mcp get brave-search"
Write-Host "3. Ask Claude: 用 brave-search 搜索 PUMA560，并返回前3条结果。"
