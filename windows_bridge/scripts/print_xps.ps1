param(
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$PrinterName,
  [int]$Copies = 1,
  [Parameter(Mandatory=$true)][string]$ConfigOut,
  [switch]$DryRun,
  [string]$XpsOut = ""
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Printing
Add-Type -AssemblyName ReachFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework

function Read-Ticket($ticket) {
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
  return [pscustomobject]@{
    media = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageMediaSize*" } | ForEach-Object { $_.Value }) -join ","
    orientation = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageOrientation*" } | ForEach-Object { $_.Value }) -join ","
    resolution = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageResolution*" } | ForEach-Object { $_.Value }) -join ","
    cut = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*DocumentCUTTERCONTROL*" } | ForEach-Object { $_.Value }) -join ","
  }
}

$server = New-Object System.Printing.LocalPrintServer
$queue = $server.GetPrintQueue($PrinterName)
$ticket = $queue.UserPrintTicket
if ($null -eq $ticket) { throw "Per-user PrintTicket unavailable: $PrinterName" }

# Validate the exact ticket against the installed driver before creating output.
$mergeMethod = $queue.GetType().GetMethod(
  "MergeAndValidatePrintTicket",
  [Type[]]@([System.Printing.PrintTicket], [System.Printing.PrintTicket], [System.Printing.PrintTicketScope])
)
if ($null -eq $mergeMethod) { throw "MergeAndValidatePrintTicket overload unavailable" }
$validation = $mergeMethod.Invoke(
  $queue, [object[]]@($ticket, $ticket, [System.Printing.PrintTicketScope]::Job)
)
if ($null -eq $validation) { throw "Driver returned no validation result" }
$validated = $validation.ValidatedPrintTicket
$conflict = $validation.ConflictStatus
if ($null -eq $validated) { throw "Driver returned no validated PrintTicket" }
if ($conflict -ne [System.Printing.ConflictStatus]::NoConflict) {
  throw "Blocked: driver ticket merge conflict: $conflict"
}
$requested = Read-Ticket $ticket
$accepted = Read-Ticket $validated
$privateCutUnverified = $false
foreach ($field in @("media", "orientation", "resolution")) {
  if ([string]$requested.$field -ne [string]$accepted.$field) {
    throw "Blocked: driver overrode $field ($($requested.$field) -> $($accepted.$field))"
  }
}
if ([string]$requested.cut -ne [string]$accepted.cut) {
  if (-not $DryRun) {
    throw "Blocked: driver did not preserve private cut feature ($($requested.cut) -> $($accepted.cut))"
  }
  $privateCutUnverified = $true
}
if ($requested.media -notlike "*PR_4x6*") { throw "Blocked: requested media is not PR_4x6 ($($requested.media))" }
if ($requested.orientation -notlike "*Portrait*") { throw "Blocked: requested orientation is not Portrait ($($requested.orientation))" }
if ($requested.resolution -notlike "*Option1*") { throw "Blocked: requested resolution is not 300x300 ($($requested.resolution))" }
if ($requested.cut -notlike "*CUT_STANDARD*") { throw "Blocked: requested cut is not CUT_STANDARD ($($requested.cut))" }

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

$mode = if ($DryRun) { "dry_run_xps_file" } else { "spooler_job" }
if ($DryRun) {
  if ([string]::IsNullOrWhiteSpace($XpsOut)) { throw "XpsOut is required for DryRun" }
  Remove-Item -Force -ErrorAction SilentlyContinue $XpsOut
  $xps = New-Object System.Windows.Xps.Packaging.XpsDocument($XpsOut, [System.IO.FileAccess]::ReadWrite)
  $writer = [System.Windows.Xps.Packaging.XpsDocument]::CreateXpsDocumentWriter($xps)
  $writer.Write($page)
  $xps.Close()
} else {
  $writer = [System.Printing.PrintQueue]::CreateXpsDocumentWriter($queue)
  for ($i = 0; $i -lt $Copies; $i++) { $writer.Write($page, $ticket) }
}

$config = [pscustomobject]@{
  mechanism = if ($DryRun) { "XpsDocumentWriter to XPS file (dry-run)" } else { "XpsDocumentWriter+explicit_PrintTicket" }
  mode = $mode
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
  ticket_media = $requested.media
  ticket_orientation = $requested.orientation
  ticket_resolution = $requested.resolution
  ticket_cut = $requested.cut
  driver_conflict = [string]$conflict
  driver_validated = $true
  driver_accepted_media = $accepted.media
  driver_accepted_orientation = $accepted.orientation
  driver_accepted_resolution = $accepted.resolution
  driver_accepted_cut = $accepted.cut
  private_vendor_cut_confirmed = (-not $privateCutUnverified)
  private_vendor_cut_note = if ($privateCutUnverified) { "ValidatedPrintTicket omitted private DNP cut namespace; dry-run geometry only." } else { "" }
  effective_settings_verified = $false
  physical_calibrated = $false
  physical_completion = "unverified"
  spooler_acceptance = if ($DryRun) { "not_submitted" } else { "accepted_by_script" }
}
$config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigOut -Encoding UTF8
$config | ConvertTo-Json -Depth 5 -Compress
