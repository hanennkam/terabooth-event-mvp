# Run as Administrator. Opens the bridge TCP port on the Private profile only.
param([int]$Port = 8787)
$ErrorActionPreference = "Stop"
$ruleName = "Terabooth Print Bridge $Port"
$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existing) { Remove-NetFirewallRule -DisplayName $ruleName }
New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Private
Write-Host "Firewall rule created: $ruleName (Private profile, TCP 8787)"
