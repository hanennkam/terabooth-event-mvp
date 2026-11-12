param(
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$PrinterName,
  [int]$Copies = 1
)
Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile((Resolve-Path $ImagePath))
try {
  $doc = New-Object System.Drawing.Printing.PrintDocument
  $doc.PrinterSettings.PrinterName = $PrinterName
  if (-not $doc.PrinterSettings.IsValid) { throw "Printer not valid: $PrinterName" }
  $doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0,0,0,0)
  # 4x6 inches at 1/100 inch units
  $doc.DefaultPageSettings.PaperSize = New-Object System.Drawing.Printing.PaperSize("4x6", 400, 600)
  $doc.DefaultPageSettings.Landscape = $false
  $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController
  $doc.add_PrintPage({
    param($sender, $e)
    $e.Graphics.DrawImage($image, 0, 0, $e.PageBounds.Width, $e.PageBounds.Height)
    $e.HasMorePages = $false
  })
  for ($i = 0; $i -lt $Copies; $i++) { $doc.Print() }
  Write-Output "submitted"
} finally {
  $image.Dispose()
  if ($doc) { $doc.Dispose() }
}
