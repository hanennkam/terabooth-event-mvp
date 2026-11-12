# Start the Terabooth Print Bridge on Windows.
param([int]$Port = 8787)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

# Load optional .env from the windows_bridge directory. Explicit process
# environment variables take precedence over .env values.
if (Test-Path ".env") {
    Get-Content ".env" | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { return }
        $eq = $line.IndexOf("=")
        if ($eq -lt 1) { return }
        $name = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()
        if ($value.Length -ge 2) {
            if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }
        if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

if (-not (Test-Path ".\.venv\Scripts\python.exe")) {
    throw "Run scripts\install_windows.ps1 first."
}
if (-not $env:TERABOOTH_PRINTER) { $env:TERABOOTH_PRINTER = "spooler" }
if (-not $env:TERABOOTH_PRINTER_NAME) { $env:TERABOOTH_PRINTER_NAME = "DNP DS-RX1HS" }
if (-not $env:TERABOOTH_DATA_DIR) { $env:TERABOOTH_DATA_DIR = (Join-Path (Get-Location) "data") }
if (-not $env:TERABOOTH_API_TOKEN -or $env:TERABOOTH_API_TOKEN -match "change-me") {
    Write-Warning "TERABOOTH_API_TOKEN is missing or a placeholder. Set a long random token before the event."
}
if (-not $env:TERABOOTH_DELIVERY_SECRET -or $env:TERABOOTH_DELIVERY_SECRET -match "change-me|dev-secret") {
    Write-Warning "TERABOOTH_DELIVERY_SECRET is missing or a placeholder. Set a long random secret before the event."
}
if ($env:TERABOOTH_PRINTER -eq "mock") {
    Write-Warning "TERABOOTH_PRINTER=mock: this is NOT a physical DNP printer."
}
if ($env:TERABOOTH_PUBLIC_BASE_URL -match 'localhost|127\.0\.0\.1') {
    throw "TERABOOTH_PUBLIC_BASE_URL must be the Windows LAN IP, not localhost."
}
if ($PSBoundParameters.ContainsKey("Port")) {
    $env:TERABOOTH_PORT = "$Port"
}
if (-not $env:TERABOOTH_HOST) { $env:TERABOOTH_HOST = "0.0.0.0" }
Write-Host "Printer mode: $env:TERABOOTH_PRINTER / $env:TERABOOTH_PRINTER_NAME"
& .\.venv\Scripts\python.exe scripts/run_bridge.py
