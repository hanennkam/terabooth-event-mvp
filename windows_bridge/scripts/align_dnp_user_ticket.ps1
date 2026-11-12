param(
  [string]$QueueName = "DS-RX1"
)
# Supported WPF printer-ticket path. Changes ONLY the per-user cut selection.
# Machine defaults are not modified. A backup of the previous user ticket is
# written outside the repository.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Printing
$server = New-Object System.Printing.LocalPrintServer
$queue = $server.GetPrintQueue($QueueName)
$ticket = $queue.UserPrintTicket
if ($null -eq $ticket) { throw "No per-user PrintTicket for $QueueName" }
$stream = $ticket.GetXmlStream()
$reader = New-Object System.IO.StreamReader($stream)
$text = $reader.ReadToEnd()
$reader.Dispose()
$stream.Dispose()
$backup = Join-Path $env:TEMP ("terabooth-{0}-user-ticket-{1}.xml" -f $QueueName, (Get-Date -Format "yyyyMMdd-HHmmss"))
Set-Content -Path $backup -Value $text -Encoding UTF8
if ($text -notmatch 'CUT_2INCH|CUT_STANDARD') {
  throw "Cut feature not present in per-user ticket; no change made."
}
$updated = $text -replace 'name="ns0000:CUT_2INCH"', 'name="ns0000:CUT_STANDARD"'
if ($updated -notmatch 'CUT_STANDARD') {
  throw "Could not set CUT_STANDARD; no change made."
}
$bytes = [System.Text.Encoding]::UTF8.GetBytes($updated)
$memory = New-Object System.IO.MemoryStream(,$bytes)
$newTicket = New-Object System.Printing.PrintTicket($memory)
$queue.UserPrintTicket = $newTicket
$queue.Commit()
Write-Output "Per-user ticket cut updated to CUT_STANDARD. Backup: $backup"
Write-Output "Queue: $QueueName"
