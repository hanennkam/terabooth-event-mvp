# Submit one real print through the Windows spooler adapter.
param(
  [string]$ImagePath = "",
  [string]$PrinterName = "DNP DS-RX1HS"
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
if (-not $ImagePath) { $ImagePath = Join-Path (Get-Location) "data\test-4x6-calibration.jpg" }
if (-not (Test-Path $ImagePath)) {
    throw "Test image not found: $ImagePath. Run: .\.venv\Scripts\python.exe scripts\make_test_sheet.py"
}
Write-Host "Printing $ImagePath to $PrinterName"
& "$PSScriptRoot\print_image.ps1" -ImagePath $ImagePath -PrinterName $PrinterName -Copies 1
Write-Host "Spooler submission returned. VERIFY THE PHYSICAL PRINT."
