param(
  [string]$QueueName = "DS-RX1"
)
$ErrorActionPreference = "Stop"

function Get-TicketSelection($ticket, [string]$pattern) {
  if ($null -eq $ticket) { return $null }
  try {
    $stream = $ticket.GetXmlStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $text = $reader.ReadToEnd()
    $reader.Dispose()
    $stream.Dispose()
    $xml = [xml]$text
    foreach ($f in $xml.PrintTicket.Feature) {
      if ([string]$f.name -like $pattern) {
        $option = @($f.Option) | Select-Object -First 1
        if ($option) { return [string]$option.name }
      }
    }
  } catch { }
  return $null
}

function Get-CapabilityOptions($capabilities, $cfg, [string]$pattern) {
  $text = ""
  if ($null -ne $cfg -and $cfg.PrintCapabilitiesXML) {
    $text = [string]$cfg.PrintCapabilitiesXML
  }
  if (-not $text -and $null -ne $capabilities) {
    try {
      $stream = $capabilities.GetXmlStream()
      $reader = New-Object System.IO.StreamReader($stream)
      $text = $reader.ReadToEnd()
      $reader.Dispose()
      $stream.Dispose()
    } catch { }
  }
  if (-not $text) { return @() }
  $feature = [regex]::Match(
    $text,
    '<(?:psf:)?Feature\s+name="[^"]*' + [regex]::Escape($pattern) + '[^"]*"[^>]*>(.*?)</(?:psf:)?Feature>',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if (-not $feature.Success) { return @() }
  $options = [regex]::Matches(
    $feature.Groups[1].Value,
    '<(?:psf:)?Option\s+name="([^"]+)"'
  )
  return @($options | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
}

function Ticket-Object($label, $ticket) {
  return [pscustomobject]@{
    source = $label
    available = ($null -ne $ticket)
    media = [string](Get-TicketSelection $ticket "*PageMediaSize*")
    orientation = [string](Get-TicketSelection $ticket "*PageOrientation*")
    resolution = [string](Get-TicketSelection $ticket "*PageResolution*")
    cut = [string](Get-TicketSelection $ticket "*DocumentCUTTERCONTROL*")
  }
}

try {
  Add-Type -AssemblyName System.Printing
  $xpsAvailable = $true
  try { Add-Type -AssemblyName ReachFramework } catch { $xpsAvailable = $false }
  $server = New-Object System.Printing.LocalPrintServer
  $queue = $server.GetPrintQueue($QueueName)
  $p = Get-Printer -Name $QueueName
  $cfg = Get-PrintConfiguration -PrinterName $QueueName
  $drv = Get-PrinterDriver -Name $p.DriverName
  $machine = Ticket-Object "machine_default" $queue.DefaultPrintTicket
  $user = Ticket-Object "user_default" $queue.UserPrintTicket
  $caps = $queue.GetPrintCapabilities()
  $capMedia = @(Get-CapabilityOptions $caps $cfg "PageMediaSize")
  $capOrient = @(Get-CapabilityOptions $caps $cfg "PageOrientation")
  $capRes = @(Get-CapabilityOptions $caps $cfg "PageResolution")
  $capCut = @(Get-CapabilityOptions $caps $cfg "DocumentCUTTERCONTROL")
  $jobs = @(Get-PrintJob -PrinterName $QueueName -ErrorAction SilentlyContinue)
  $blockers = @()
  if ([string]$p.PrinterStatus -ne "Normal") { $blockers += "printer_status" }
  if ([bool]$p.WorkOffline) { $blockers += "work_offline" }
  if ([string]$user.media -ne "ns0000:PR_4x6") { $blockers += "user_media_not_PR_4x6" }
  if ([string]$machine.media -ne "ns0000:PR_4x6") { $blockers += "machine_media_not_PR_4x6" }
  if ([string]$user.orientation -ne "psk:Portrait") { $blockers += "user_orientation_not_portrait" }
  if ([string]$machine.orientation -ne "psk:Portrait") { $blockers += "machine_orientation_not_portrait" }
  if ([string]$user.resolution -ne "ns0000:Option1") { $blockers += "user_resolution_not_300x300" }
  if ([string]$machine.resolution -ne "ns0000:Option1") { $blockers += "machine_resolution_not_300x300" }
  if ([string]$user.cut -ne "ns0000:CUT_STANDARD") { $blockers += "user_cut_not_standard" }
  if ([string]$machine.cut -ne "ns0000:CUT_STANDARD") { $blockers += "machine_cut_not_standard" }
  if ($capMedia -notcontains "ns0000:PR_4x6") { $blockers += "capability_missing_PR_4x6" }
  if ($capCut -notcontains "ns0000:CUT_STANDARD") { $blockers += "capability_missing_CUT_STANDARD" }
  if (-not $xpsAvailable) { $blockers += "xps_printticket_unavailable" }
  $configurationReady = ($blockers.Count -eq 0)
  [pscustomobject]@{
    available = $true
    ready = $configurationReady
    physical_ready = $false
    configuration_ready = $configurationReady
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
    media = [string]$user.media
    orientation = [string]$user.orientation
    resolution = [string]$user.resolution
    cut = [string]$user.cut
    queued_jobs = $jobs.Count
    machine_default = $machine
    user_default = $user
    capabilities = [pscustomobject]@{
      media = $capMedia
      orientation = $capOrient
      resolution = $capRes
      cut = $capCut
    }
    job_request = [pscustomobject]@{
      media = "PR_4x6"
      orientation = "Portrait"
      resolution = "300x300"
      cut = "CUT_STANDARD"
    }
    job_level = [pscustomobject]@{
      available = [bool]$xpsAvailable
      mechanism = "XpsDocumentWriter + explicit per-user PrintTicket"
      requested_media = "PR_4x6"
      requested_orientation = "Portrait"
      requested_resolution = "300x300"
      requested_cut = "CUT_STANDARD"
      effective_settings_verified = $false
      physical_calibrated = $false
      reason = "No job submitted; effective per-job settings remain unverified until physical calibration."
    }
    blockers = @($blockers)
    query_error = ""
  } | ConvertTo-Json -Depth 8 -Compress
} catch {
  [pscustomobject]@{
    available = $false
    ready = $false
    physical_ready = $false
    configuration_ready = $false
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
    machine_default = $null
    user_default = $null
    capabilities = $null
    job_request = $null
    job_level = $null
    blockers = @("preflight_query_failed")
    query_error = $_.Exception.Message
  } | ConvertTo-Json -Depth 8 -Compress
}
