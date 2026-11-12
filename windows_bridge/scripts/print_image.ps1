param(
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$PrinterName,
  [int]$Copies = 1
)
$ErrorActionPreference = "Stop"
$configOut = Join-Path $env:TEMP ("terabooth-print-job-{0}.json" -f (Get-Date -Format "yyyyMMddHHmmssfff"))
& (Join-Path $PSScriptRoot "print_xps.ps1") -ImagePath $ImagePath -PrinterName $PrinterName -Copies $Copies -ConfigOut $configOut
