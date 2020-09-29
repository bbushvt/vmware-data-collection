param ([string] $vcenter, [string] $username, [string] $password, [int] $metricDays = 7, [switch] $csv, [switch] $anon)

function ExitWithCode {
    param
    (
        $exitcode
    )

    $host.SetShouldExit($exitcode)
    exit
}

$anonTables = @{
    cluster    = @{
        table  = @{}
        index  = 0
        prefix = "cluster"
    }
    datacenter = @{
        table  = @{}
        index  = 0
        prefix = "datacenter"
    }
}
Function LookupName($table, $name) {
    if ($anon) {
        if (-NOT $table.table.ContainsKey($name)) {
            $table.table.add($name, $table.prefix + $table.index)
            $table.index += 1
        }
        return ($table.table)[$name]
    }
    else {
        return $name
    }
}

Function IIf($If, $Right, $Wrong) { If ($If) { $Right } Else { $Wrong } }

Function Get-StringHash([String] $data) {
    $sha1 = New-Object System.Security.Cryptography.SHA1CryptoServiceProvider
    $hashByteArray = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))
    foreach ($byte in $hashByteArray) {
        $result += "{0:X2}" -f $byte
    }
    return $result;
}

# Check to make sure we have all the parameters we need
if ('' -eq $vcenter) {
    $vcenter = Read-Host "Hostname or IP address for vCenter"
}
if ('' -eq $username) {
    $username = Read-Host "vCenter Username"
}
if ('' -eq $password) {
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
#$allData = "" | Select-Object vms, hosts
$allData = @{
    VMware = @{
        Clusters = @()
    }
}

Function Add-DataNode($type, $data) {
    $found = $false
    foreach ($cluster in $allData.VMware.Clusters) {        
        if ($cluster.Name -eq $data.Cluster) {
            $cluster[$type] += $data
            $found = $true
        }
    }

    if ($found -eq $false) {
        $dataNode = @{
            Name  = $data.Cluster
            vms   = @()
            Hosts = @()
        }
        $dataNode[$type] += $data
        $allData.VMware.Clusters += $dataNode
    }
}

$allvms = @()
$allhosts = @()

$hosts = Get-VMHost
$vms = Get-Vm

foreach ($vmHost in $hosts) {
    # TODO - BCBUSH - Remove me
    #$hoststat = "" | Select-Object HostName, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin, NumCpu, CpuTotalGhz
    $hoststat = @{}

    $hoststat.HostName = (IIF $anon (Get-StringHash $vmHost.name) $vmHost.name)
    $hoststat.HostID = $vmHost.ID.substring(11)
  
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
    $hoststat.Cluster = LookupName $anonTables.cluster $vmHost.Parent.Name
    $hoststat.MetricDays = $metricDays
    #$allhosts += $hoststat
    Add-DataNode "Hosts" $hoststat
}

foreach ($vm in $vms) {
    # TODO - BCBUSH - Remove me
    #$vmstat = "" | Select-Object Id, VmName, GuestOS, PowerState, NumCPUs, CpuGhz, MemoryGB, HarddiskGB, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin
    $vmstat = @{}
    
    $vmstat.VMID = $vm.ID.substring(15)
    $vmstat.HostID = $vm.VmHostId.substring(11)
    $vmstat.VmName = (IIF $anon (Get-StringHash $vm.Name) $vm.Name)
    $vmstat.Cluster = LookupName $anonTables.cluster (Get-VMHost -VM IBMCli).parent.name
    $vmstat.Datacenter = LookupName $anonTables.datacenter (Get-Datacenter -VM IBMCli).Name

    $vmstat.GuestOS = IIF $vm.Guest.OSFullname.length $vm.Guest.OSFullname (Get-View -viewtype VirtualMachine -filter @{"Name" = $vm.Name }).Config.GuestFullName
    $vmstat.Powerstate = $vm.PowerState
    $vmstat.NumCPUs = $vm.NumCPU
    $vmstat.MemoryGB = $vm.MemoryGB
    $vmstat.CpuGhz = [math]::round($vm.NumCPU * $vmHost.CpuTotalMhz / $vmHost.NumCpu / 1000, 2)
    $vmstat.VDiskCount = (Get-HardDisk $vm.Name).count

    $vmstat.StorageAllocated = [math]::round($vm.ProvisionedSpaceGB, 2)
    $vmstat.StorageUsed = [math]::round($vm.UsedSpaceGB, 2)
    
    if ($vm.PowerState) {
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
        $vmstat.MetricDays = $metricDays
    }
    else {
        $vmstat.CPUMax = 0.0
        $vmstat.CPUAvg = 0.0
        $vmstat.CPUMin = 0.0
        $vmstat.MemMax = 0.0
        $vmstat.MemAvg = 0.0
        $vmstat.MemMin = 0.0
        $vmstat.MetricDays = 0
    }
    
    #$allvms += $vmstat
    Add-DataNode "vms" $vmstat
}
# TODO - BCBUSH - Remove me
#$allData.vms = $allvms | Select-Object ID, VmName, GuestOS, PowerState, NumCPUs, CPUGhz, MemoryGB, HarddiskGB, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin
#$allData.hosts = $allhosts | Select-Object HostName, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin, NumCpu, CpuTotalGhz 
#$allData.vms = $allvms
#$allData.hosts = $allhosts 


if ($csv) {
    $allhosts | Select-Object HostName, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin | Export-Csv "Hosts.csv" -noTypeInformation
    $allvms | Select-Object VmName, PowerState, NumCPUs, MemoryGB, HarddiskGB, MemMax, MemAvg, MemMin, CPUMax, CPUAvg, CPUMin | Export-Csv "VMs10.csv" -noTypeInformation
}

Write-Output $allData | ConvertTo-Json -Depth 10 
#Write-Host ($allData | Format-Table | Out-String)
Exit 0