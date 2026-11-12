# Installs runtime-only dependencies into a local venv after explicit operator approval.
param([switch]$Confirm)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
if (-not $Confirm) {
    Write-Error "Refusing to install without -Confirm. Review this script and rerun with -Confirm."
}
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python 3.11+ 64-bit is required. Install it manually, then rerun."
}
$version = python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
if ([version]$version -lt [version]"3.11") {
    Write-Error "Python 3.11+ is required; found $version."
}
python -m venv .venv
& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -r requirements-runtime.txt
Write-Output "Runtime installed. No pytest/httpx or printer drivers were installed."
