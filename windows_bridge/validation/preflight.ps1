# Read-only Windows preflight. Does not install or modify software.
$ErrorActionPreference = "Stop"
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'"
$nets = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null }
Write-Output "=== Terabooth Windows preflight ==="
Write-Output ("Windows: {0} build {1}" -f $os.Caption, $os.BuildNumber)
Write-Output ("Manufacturer/model: {0} {1}" -f $cs.Manufacturer, $cs.Model)
Write-Output ("CPU: {0}" -f ($cpu | ForEach-Object { $_.Name } | Select-Object -First 1))
Write-Output ("RAM bytes: {0}" -f $cs.TotalPhysicalMemory)
Write-Output ("System drive: {0} free={1} total={2}" -f $env:SystemDrive, $disk.FreeSpace, $disk.Size)
Write-Output "Network:"
$nets | ForEach-Object {
    Write-Output ("  {0} / {1}" -f $_.InterfaceAlias, (($_.IPv4Address.IPAddress) -join ", "))
}
Write-Output "Python:"
$py = Get-Command python -ErrorAction SilentlyContinue
$py3 = Get-Command py -ErrorAction SilentlyContinue
if ($py) {
    Write-Output ("  python: " + (& python --version 2>&1))
    Write-Output ("  architecture: " + (& python -c "import platform; print(platform.architecture()[0])" 2>&1))
    Write-Output ("  executable: " + $py.Source)
} elseif ($py3) {
    Write-Output ("  py launcher: " + (& py -3 --version 2>&1))
    Write-Output ("  executable: " + $py3.Source)
} else {
    Write-Output "  python: NOT FOUND"
}
if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
    Get-PhysicalDisk | Select-Object FriendlyName, MediaType, Size | Format-Table | Out-String | Write-Output
}
