param(
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$PrinterName,
  [int]$Copies = 1,
  [Parameter(Mandatory=$true)][string]$ConfigOut
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Printing
Add-Type -AssemblyName ReachFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework

$server = New-Object System.Printing.LocalPrintServer
$queue = $server.GetPrintQueue($PrinterName)
$ticket = $queue.UserPrintTicket
if ($null -eq $ticket) { throw "Per-user PrintTicket unavailable: $PrinterName" }

# Capture and validate the exact ticket requested for this job.
$stream = $ticket.GetXmlStream()
$reader = New-Object System.IO.StreamReader($stream)
$text = $reader.ReadToEnd()
$reader.Dispose()
$stream.Dispose()
$xml = [xml]$text
$feature = @{}
foreach ($f in $xml.PrintTicket.Feature) {
  $option = @($f.Option) | Select-Object -First 1
  $feature[[string]$f.name] = if ($option) { [string]$option.name } else { "" }
}
$media = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageMediaSize*" } | ForEach-Object { $_.Value }) -join ","
$orientation = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageOrientation*" } | ForEach-Object { $_.Value }) -join ","
$resolution = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageResolution*" } | ForEach-Object { $_.Value }) -join ","
$cut = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*DocumentCUTTERCONTROL*" } | ForEach-Object { $_.Value }) -join ","
if ($media -notlike "*PR_4x6*") { throw "Blocked: ticket media is not PR_4x6 ($media)" }
if ($orientation -notlike "*Portrait*") { throw "Blocked: ticket orientation is not Portrait ($orientation)" }
if ($resolution -notlike "*Option1*") { throw "Blocked: ticket resolution is not 300x300 ($resolution)" }
if ($cut -notlike "*CUT_STANDARD*") { throw "Blocked: ticket cut is not CUT_STANDARD ($cut)" }

$image = New-Object System.Windows.Media.Imaging.BitmapImage
$image.BeginInit()
$image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
$image.UriSource = New-Object System.Uri((Resolve-Path $ImagePath).Path)
$image.EndInit()
$image.Freeze()

# 4x6 at XPS's 96 DPI. Portrait, full page, uniform scaling (no stretch).
$page = New-Object System.Windows.Documents.FixedPage
$page.Width = 384
$page.Height = 576
$page.Background = [System.Windows.Media.Brushes]::White
$visual = New-Object System.Windows.Controls.Image
$visual.Source = $image
$visual.Stretch = [System.Windows.Media.Stretch]::Uniform
$visual.Width = 384
$visual.Height = 576
[System.Windows.Documents.FixedPage]::SetLeft($visual, 0)
[System.Windows.Documents.FixedPage]::SetTop($visual, 0)
$page.Children.Add($visual)

$writer = [System.Windows.Xps.XpsDocumentWriter]::CreateXpsDocumentWriter($queue)
for ($i = 0; $i -lt $Copies; $i++) {
  $writer.Write($page, $ticket)
}

$config = [pscustomobject]@{
  mechanism = "XpsDocumentWriter+explicit_PrintTicket"
  queue = $PrinterName
  image = (Resolve-Path $ImagePath).Path
  page_inches = "4x6"
  page_px_96dpi = "384x576"
  orientation = "Portrait"
  resolution = "300x300"
  media = "PR_4x6"
  cut = "CUT_STANDARD"
  copies = $Copies
  ticket_source = "per-user PrintTicket"
  ticket_media = $media
  ticket_orientation = $orientation
  ticket_resolution = $resolution
  ticket_cut = $cut
  effective_job_settings_verified = $false
  physical_calibrated = $false
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigOut -Encoding UTF8
$config | ConvertTo-Json -Depth 5 -Compress
