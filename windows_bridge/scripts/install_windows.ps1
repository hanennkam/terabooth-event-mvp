# Terabooth Print Bridge - Windows install (run in PowerShell)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "Python 3.11+ is required and was not found on PATH."
}
python --version
$version = python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ([version]$version -lt [version]"3.11") {
    throw "Python 3.11 or newer is required; found $version."
}
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
# Runtime only: no pytest/httpx/dev tooling on the low-resource laptop.
.\.venv\Scripts\python.exe -m pip install -r requirements-runtime.txt

if (-not (Test-Path ".env") -and (Test-Path "..\.env.example")) {
    Copy-Item "..\.env.example" ".env"
    Write-Host "Created .env from ..\.env.example"
    Write-Host "Set TERABOOTH_PRINTER=spooler (or hotfolder) and replace placeholder tokens/secrets."
}

Write-Host ""
Write-Host "Installed. Next:"
Write-Host "  1. Edit .env: set TERABOOTH_PRINTER=spooler (or hotfolder), printer name,"
Write-Host "     TERABOOTH_API_TOKEN, TERABOOTH_DELIVERY_SECRET, and the Windows LAN URL."
Write-Host "  2. Run scripts\firewall.ps1 as Administrator."
Write-Host "  3. Run scripts\run_windows.ps1"
