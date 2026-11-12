# Disposable guest-phone LAN smoke test. Uses a separate temp DB and port 8788.
# Does not stop or modify the production bridge on 8787.
param(
    [int]$Port = 8788,
    [string]$PublicUrl = "http://192.168.8.192:8788",
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if ($Port -eq 8787) {
    throw "Refusing to reuse the production port 8787. Use 8788 or another disposable port."
}
if ($PublicUrl -match 'localhost|127\.0\.0\.1') {
    throw "PublicUrl must be the LAN address, not localhost."
}
$py = ".\.venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    throw "Run validation\install_runtime.ps1 -Confirm first."
}

# Independent, cryptographically random secrets. Never print them.
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $apiBytes = New-Object byte[] 32
    $deliveryBytes = New-Object byte[] 32
    $rng.GetBytes($apiBytes)
    $rng.GetBytes($deliveryBytes)
    $env:TERABOOTH_API_TOKEN = [Convert]::ToBase64String($apiBytes)
    $env:TERABOOTH_DELIVERY_SECRET = [Convert]::ToBase64String($deliveryBytes)
} finally {
    $rng.Dispose()
}
$env:TERABOOTH_PRINTER = "mock"

Write-Host "=== Disposable Guest Phone Smoke ==="
Write-Host "Production port 8787 is read only; this script does not stop or modify it."
$prod = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue
if ($prod) {
    Write-Host "Production bridge observed on port 8787 (left untouched)."
} else {
    Write-Host "No listener observed on 8787; continuing with isolated 8788 only."
}
Write-Host "Disposable listener will bind 0.0.0.0:$Port."
Write-Host "Guest LAN URL: $PublicUrl"
Write-Host "Printer: mock. Data: fresh temporary directory owned by this run."
Write-Host "The guest URL is sensitive; do not post it publicly."
Write-Host ""

if ($SelfTest) {
    & $py validation\guest_phone_smoke.py --port $Port --public-url $PublicUrl --self-test
} else {
    & $py validation\guest_phone_smoke.py --port $Port --public-url $PublicUrl
}
exit $LASTEXITCODE
