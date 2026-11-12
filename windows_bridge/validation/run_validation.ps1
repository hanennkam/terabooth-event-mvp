param([string]$Port = "18787")
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
$py = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) { throw "Run validation\install_runtime.ps1 -Confirm first." }
& $py validation\validate_runtime.py
& $py validation\validate_bridge.py --port $Port --keep-report
