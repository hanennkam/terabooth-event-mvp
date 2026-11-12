param(
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$PrinterName,
  [int]$Copies = 1,
  [Parameter(Mandatory=$true)][string]$ConfigOut
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile((Resolve-Path $ImagePath))
try {
  $doc = New-Object System.Drawing.Printing.PrintDocument
  $doc.PrinterSettings.PrinterName = $PrinterName
  if (-not $doc.PrinterSettings.IsValid) { throw "Printer not valid: $PrinterName" }
  $page = $doc.DefaultPageSettings
  if ($null -eq $page.PaperSize -or $page.PaperSize.PaperName -notmatch "4x6") {
    throw "Blocked: driver default paper is not PR_4x6 ($($page.PaperSize.PaperName))"
  }
  if ($page.Landscape) { throw "Blocked: driver default page is landscape" }
  if ($Copies -lt 1 -or $Copies -gt 2) { throw "Blocked: copies must be 1 or 2" }
  # Do not set PaperSize, Landscape, margins or DNP private features. Those are
  # managed by the Windows printer preferences.
  $doc.PrinterSettings.Copies = $Copies
  $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController
  $doc.add_PrintPage({
    param($sender, $e)
    $b = $e.PageBounds
    $scale = [Math]::Min($b.Width / $image.Width, $b.Height / $image.Height)
    $w = [int][Math]::Round($image.Width * $scale)
    $h = [int][Math]::Round($image.Height * $scale)
    $x = $b.Left + [int][Math]::Floor(($b.Width - $w) / 2)
    $y = $b.Top + [int][Math]::Floor(($b.Height - $h) / 2)
    $e.Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $e.Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $e.Graphics.DrawImage($image, $x, $y, $w, $h)
    $e.HasMorePages = $false
  })
  $doc.Print()
  $config = [pscustomobject]@{
    mechanism = "driver_managed_PrintDocument"
    mode = "spooler_job"
    queue = $PrinterName
    image = (Resolve-Path $ImagePath).Path
    paper_name = [string]$page.PaperSize.PaperName
    paper_width = $page.PaperSize.Width
    paper_height = $page.PaperSize.Height
    landscape = [bool]$page.Landscape
    copies = $Copies
    paper_overridden = $false
    orientation_overridden = $false
    margins_overridden = $false
    private_vendor_features_set = $false
    cut_source = "Windows DNP driver preferences"
    cut_verified_software = $false
    physical_completion = "unverified"
    spooler_acceptance = "accepted_by_script"
  }
  $config | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigOut -Encoding UTF8
  $config | ConvertTo-Json -Depth 5 -Compress
} finally {
  $image.Dispose()
  if ($doc) { $doc.Dispose() }
}
