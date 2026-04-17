@echo off
setlocal

set "ROOT=%~dp0.."
set "PY=%ROOT%\.venv\Scripts\python.exe"
set "SERVER=%ROOT%\tools\brave_mcp_server.py"

if not exist "%PY%" (
  echo Python venv not found: "%PY%" 1>&2
  echo Run setup_brave_mcp.ps1 first. 1>&2
  exit /b 1
)

"%PY%" "%SERVER%"
