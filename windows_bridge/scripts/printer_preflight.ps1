param(
  [string]$QueueName = "DS-RX1"
)
$ErrorActionPreference = "Stop"
try {
  $p = Get-Printer -Name $QueueName
  $cfg = Get-PrintConfiguration -PrinterName $QueueName
  $drv = Get-PrinterDriver -Name $p.DriverName
  $feature = @{}
  if ($cfg.PrintTicketXML) {
    $ticket = [xml]$cfg.PrintTicketXML
    foreach ($f in $ticket.PrintTicket.Feature) {
      $names = @($f.Option | ForEach-Object { [string]$_.name }) -join ","
      $feature[[string]$f.name] = $names
    }
  }
  $media = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageMediaSize*" } | ForEach-Object { $_.Value }) -join ","
  $orientation = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageOrientation*" } | ForEach-Object { $_.Value }) -join ","
  $resolution = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*PageResolution*" } | ForEach-Object { $_.Value }) -join ","
  $cut = @($feature.GetEnumerator() | Where-Object { $_.Key -like "*DocumentCUTTERCONTROL*" } | ForEach-Object { $_.Value }) -join ","
  $jobs = @(Get-PrintJob -PrinterName $QueueName -ErrorAction SilentlyContinue)
  [pscustomobject]@{
    available = $true
    queue_exists = $true
    queue_name = [string]$p.Name
    driver_name = [string]$p.DriverName
    driver_manufacturer = [string]$drv.Manufacturer
    driver_version = [string]$drv.DriverVersion
    port_name = [string]$p.PortName
    printer_status = [string]$p.PrinterStatus
    work_offline = [bool]$p.WorkOffline
    shared = [bool]$p.Shared
    paper_size = [string]$cfg.PaperSize
    media = $media
    orientation = $orientation
    resolution = $resolution
    cut = $cut
    queued_jobs = $jobs.Count
    query_error = ""
  } | ConvertTo-Json -Depth 4 -Compress
} catch {
  [pscustomobject]@{
    available = $false
    queue_exists = $false
    queue_name = $QueueName
    driver_name = ""
    driver_manufacturer = ""
    driver_version = ""
    port_name = ""
    printer_status = ""
    work_offline = $false
    shared = $false
    paper_size = ""
    media = ""
    orientation = ""
    resolution = ""
    cut = ""
    queued_jobs = 0
    query_error = $_.Exception.Message
  } | ConvertTo-Json -Depth 4 -Compress
}
