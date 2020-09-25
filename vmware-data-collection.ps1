param ([string] $vcenter, [string] $username, [String] $password, [int] $metricDays, [switch] $csv, [switch] $anon)

function ExitWithCode {
    param
    (
        $exitcode
    )

    $host.SetShouldExit($exitcode)
    exit
}

Function IIf($If, $Right, $Wrong) {If ($If) {$Right} Else {$Wrong}}

Function Get-StringHash([String] $data)
{
    $sha1 = New-Object System.Security.Cryptography.SHA1CryptoServiceProvider
    $hashByteArray = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))
    foreach($byte in $hashByteArray)
    {
      $result += "{0:X2}" -f $byte
    }
    return $result;
}

# Check to make sure we have all the parameters we need
if ($null -eq $vcenter) {
    $vcenter = Read-Host "Hostname or IP address for vCenter"
}
if ($null -eq $username) {
    $username = Read-Host "vCenter Username"
}
if ($null -eq $password) {
    $ss_password = Read-Host "vCenter Password" -AsSecureString
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss_password))
}

if ($null -eq $csv) {
    $csv = $false
}

Connect-VIServer $vcenter -User $username -Password $password | Out-Null

if (0 -eq $?) {
    # Connection failed, exit with code = 99
    ExitWithCode 99
}

Write-Output "BEGIN_DATA_PARSE_SECTION"
$allData = "" | Select-Object vms, hosts
$allvms = @()
$allhosts = @()

$hosts = Get-VMHost
$vms = Get-Vm

foreach ($vmHost in $hosts) {
    $hoststat = "" | Select-Object HostName, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin, NumCpu, CpuTotalGhz

    $hoststat.HostName = (IIF $anon (Get-StringHash $vmHost.name) $vmHost.name)
  
    $statcpu = Get-Stat -Entity ($vmHost)-start (get-date).AddDays(-$metricDays) -Finish (Get-Date)-MaxSamples 10 -stat cpu.usage.average
    $statmem = Get-Stat -Entity ($vmHost)-start (get-date).AddDays(-$metricDays) -Finish (Get-Date)-MaxSamples 10 -stat mem.usage.average

    $cpu = $statcpu | Measure-Object -Property value -Average -Maximum -Minimum
    $mem = $statmem | Measure-Object -Property value -Average -Maximum -Minimum
  
    $hoststat.CPUMax = [math]::round($cpu.Maximum, 2)
    $hoststat.CPUAvg = [math]::round($cpu.Average, 2)
    $hoststat.CPUMin = [math]::round($cpu.Minimum, 2)
    $hoststat.MemMax = [math]::round($mem.Maximum, 2)
    $hoststat.MemAvg = [math]::round($mem.Average, 2)
    $hoststat.MemMin = [math]::round($mem.Minimum, 2)
    $hoststat.CpuTotalGhz = [math]::round($vmHost.CpuTotalMhz / 1000, 2)
    $hoststat.NumCpu = $vmHost.NumCpu
    $allhosts += $hoststat
}

foreach ($vm in $vms) {
    $vmstat = "" | Select-Object Id, VmName, GuestOS, PowerState, NumCPUs, CpuGhz, MemoryGB, HarddiskGB, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin
    
    $vmstat.ID = (IIF $anon (Get-StringHash $vm.ID) $vm.ID)
    $vmstat.VmName = (IIF $anon (Get-StringHash $vm.ID) $vm.ID)

    $vmstat.GuestOS = $vm.Guest.OSFullname
    $vmstat.Powerstate = $vm.powerstate
    $vmstat.NumCPUs = $vm.NumCPU
    $vmstat.MemoryGB = $vm.MemoryGB
    $vmstat.CpuGhz = [math]::round($vm.NumCPU * $vmHost.CpuTotalMhz / $vmHost.NumCpu / 1000, 2)

    $vmstat.HarddiskGB = [math]::round((Get-HardDisk -VM $vm | Measure-Object -Sum CapacityGB).Sum, 2)
    
    if ($vmstat.Powerstate) {
        $statcpu = Get-Stat -Entity ($vm)-start (get-date).AddDays(-$metricDays) -Finish (Get-Date)-MaxSamples 10 -stat "cpu.usage.average"
        $statmem = Get-Stat -Entity ($vm)-start (get-date).AddDays(-$metricDays) -Finish (Get-Date)-MaxSamples 10 -stat "mem.usage.average"
  
        $cpu = $statcpu | Measure-Object -Property value -Average -Maximum -Minimum
        $mem = $statmem | Measure-Object -Property value -Average -Maximum -Minimum
        $vmstat.CPUMax = [math]::round($cpu.Maximum, 2)
        $vmstat.CPUAvg = [math]::round($cpu.Average, 2)
        $vmstat.CPUMin = [math]::round($cpu.Minimum, 2)
        $vmstat.MemMax = [math]::round($mem.Maximum, 2)
        $vmstat.MemAvg = [math]::round($mem.Average, 2)
        $vmstat.MemMin = [math]::round($mem.Minimum, 2)
    }
    else {
        $vmstat.CPUMax = 0.0
        $vmstat.CPUAvg = 0.0
        $vmstat.CPUMin = 0.0
        $vmstat.MemMax = 0.0
        $vmstat.MemAvg = 0.0
        $vmstat.MemMin = 0.0
    }
    
    $allvms += $vmstat
}
$allData.vms = $allvms | Select-Object ID, VmName, GuestOS, PowerState, NumCPUs, CPUGhz, MemoryGB, HarddiskGB, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin
$allData.hosts = $allhosts | Select-Object HostName, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin, NumCpu, CpuTotalGhz 

if ($csv) {
    $allhosts | Select-Object HostName, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin | Export-Csv "Hosts.csv" -noTypeInformation
    $allvms | Select-Object VmName, PowerState, NumCPUs, MemoryGB, HarddiskGB, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin | Export-Csv "VMs10.csv" -noTypeInformation
}

Write-Output $allData | ConvertTo-Json

Exit 0