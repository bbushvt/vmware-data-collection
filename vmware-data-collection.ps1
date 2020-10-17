param ([string] $vcenter, [string] $username, [string] $password, [int] $metricDays = 7, [switch] $anon, [switch] $CollectStats, [string] $outputFile, [switch] $script)

function ExitWithCode {
    param
    (
        $exitcode
    )

    $host.SetShouldExit($exitcode)
    exit
}

if ('' -eq $outputFile -And -Not $script) {
    Write-Host "Error: must specify output file or script flag"
    Exit
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

Connect-VIServer $vcenter -User $username -Password $password | Out-Null

if (0 -eq $?) {
    # Connection failed, exit with code = 99
    ExitWithCode 99
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
Function Get-StringHash([String] $data) {
    $sha1 = New-Object System.Security.Cryptography.SHA1CryptoServiceProvider
    $hashByteArray = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($data))
    foreach ($byte in $hashByteArray) {
        $result += "{0:X2}" -f $byte
    }
    return $result;
}

$DatacenterHash = @{
    VmFolders   = @{}
    HostFolders = @{}
}

$VmHostMap = @{}
$ESXiHostsHash = @{}
$ClusterHash = @{}
$VMList = [System.Collections.ArrayList]::new()

$statsArray = [System.Collections.ArrayList]::new()
$statsHash = @{}
$metricDays = 7

Function IIf($If, $Right, $Wrong) { If ($If) { $Right } Else { $Wrong } }

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

Function ProcessDatacenters {
    $dcs = Get-View -ViewType Datacenter

    foreach ($dc in $dcs) {
        $DatacenterHash.VmFolders[$dc.VmFolder.value] = $dc.Name
        $DatacenterHash.HostFolders[$dc.HostFolder.value] = $dc.Name
    }
}

Function ProcessClusters {
    $clusters = Get-View -viewtype ComputeResource

    foreach ($cluster in $clusters) {
        $newCluster = @{}
        $newCluster.Parent = $cluster.Parent.value
        $newCluster.Name = $cluster.Name
        $ClusterHash[$cluster.MoRef.value] = $newCluster
    }
}

Function ProcessESXiHosts {
    $esxiHosts = Get-View -viewtype HostSystem

    foreach ($esxiHost in $esxiHosts) {
        $newESXiHost = @{}

        $newESXiHost.Name = $esxiHost.Name
        [void]$statsArray.Add($esxiHost.Name)
        $newESXiHost.Parent = $esxiHost.Parent.value
        $newESXiHost.CPUGhz = [math]::truncate($esxiHost.Hardware.CpuInfo.Hz / 1000 / 1000 / 1000 * 100) / 100
        $newESXiHost.NumCpu = $esxiHost.Hardware.CpuInfo.NumCpuCores
        $newESXiHost.CpuTotalGhz = [math]::truncate( ($esxiHost.Hardware.CpuInfo.Hz * $newESXiHost.NumCpu) / 10000000) / 100
        $newESXiHost.Cluster = $ClusterHash[$newESXiHost.Parent].Name
        $newESXiHost.MetricDays = $metricDays
        $newESXiHost.HostID = $esxiHost.MoRef.value
        $newESXiHost.CPUMax = 0.0
        $newESXiHost.CPUAvg = 0.0
        $newESXiHost.CPUMin = 0.0
        $newESXiHost.MemMax = 0.0
        $newESXiHost.MemAvg = 0.0
        $newESXiHost.MemMin = 0.0
        $newESXiHost.MetricDays = 0

        $ESXiHostsHash[$esxiHost.MoRef.value] = $newESXiHost
        
        foreach ($vm in $esxiHost.Vm.value) {
            $VmHostMap[$vm] = $esxiHost.MoRef.value
        }
    }
}

Function ProcessStats {
    if ($CollectStats -eq $true) {
        $stats = Get-Stat -Entity $StatsArray -start (get-date).AddDays(-$metricDays) -Finish (Get-Date)-MaxSamples 10 -stat cpu.usage.average, mem.usage.average
        $groupedStats = $stats | Group-Object -Property Entity, MetricId
        foreach ($stat in $groupedStats) {
            $identifier, $statType = $stat.Name -Split ", "
            if (-NOT $statsHash.ContainsKey($identifier)) {
                $statsHash[$identifier] = @{}
            }
            $statsHash[$identifier][$statType] = $stat.Group | Measure-Object -Property value -Average -Maximum -Minimum   
        }
    } 
}

Function ProcessVirtualMachines {
    $vms = Get-View -ViewType VirtualMachine
    foreach ($vm in $vms) {
        $newVM = @{}
        $newVM.VMID = $vm.MoRef.value
        $newVM.HostID = $VmHostMap[$newVM.VMID]
        $newVM.Name = $vm.Name
        $newVM.Datacenter = $DatacenterHash.HostFolders[$ClusterHash[$ESXiHostsHash[$newVM.HostID].Parent].Parent]
        $newVM.Cluster = $ClusterHash[$ESXiHostsHash[$newVM.HostID].Parent].Name
        $newVM.GuestOS = IIf $vm.Guest.GuestFullName.length $vm.Guest.GuestFullName $vm.Config.GuestFullName
        $newVM.Powerstate = $vm.Runtime.PowerState
        # Only collect stats on vms that are powered on
        if ($newVM.Powerstate -eq "poweredOn") {
            [void]$statsArray.Add($newVM.Name)
        }
        $newVM.NumCPUs = $vm.Config.Hardware.NumCPU
        $newVM.MemoryGB = $vm.Config.Hardware.MemoryMB / 1024
        $newVM.CpuGhz = [math]::round($ESXiHostsHash[$newVM.HostID].CPUGhz * $newVM.NumCPUs, 2)
        $newVM.VDiskCount = $vm.Layout.Disk.count
        $newVM.StorageUsed = [math]::Round($vm.Summary.Storage.Committed / 1073741824, 2)
        $newVM.StorageAllocated = [math]::Round( ($vm.Summary.Storage.Uncommitted / 1073741824) + $newVM.StorageUsed, 2)

        # Set default values for the stats, will overwrite later if we are getting stats on this VM
        $newVM.CPUMax = 0.0
        $newVM.CPUAvg = 0.0
        $newVM.CPUMin = 0.0
        $newVM.MemMax = 0.0
        $newVM.MemAvg = 0.0
        $newVM.MemMin = 0.0
        $newVM.MetricDays = 0
        [void]$VMList.Add($newVM)
    }   
}

Function PopulateStatsInfo($element) {
    # Check to make sure we are collecting stats
    if ($CollectStats -eq $true) {
        # Check to make sure key exists in the $statsHash            
        if ($statsHash.Contains($element.Name)) {
            $element.CPUMax = [math]::round($statsHash[$element.Name]['cpu.usage.average'].Maximum, 2)
            $element.CPUAvg = [math]::round($statsHash[$element.Name]['cpu.usage.average'].Average, 2)
            $element.CPUMin = [math]::round($statsHash[$element.Name]['cpu.usage.average'].Minimum, 2)
            $element.MemMax = [math]::round($statsHash[$element.Name]['mem.usage.average'].Maximum, 2)
            $element.MemAvg = [math]::round($statsHash[$element.Name]['mem.usage.average'].Average, 2)
            $element.MemMin = [math]::round($statsHash[$element.Name]['mem.usage.average'].Minimum, 2)
            $element.MetricDays = $metricDays

        }
    }
}

Function AnonymizeVmData($vm) {
    if ($anon) {
        $vm.Cluster = LookupName $anonTables.cluster $vm.Cluster
        $vm.Datacenter = LookupName $anonTables.datacenter $vm.Datacenter
        $vm.Name = Get-StringHash $vm.Name
    }
}

Function AnonymizeEsxiData($esxiHost) {
    if ($anon) {
        $esxiHost.Cluster = LookupName $anonTables.cluster $esxiHost.Cluster
        $esxiHost.Name = Get-StringHash $esxiHost.Name
    }
}

Function GenerateJsonData {
    # Iterate over all the hosts
    $esxiHostKeys = $ESXiHostsHash.Keys
    foreach ($esxiHostKey in $esxiHostKeys) {
        $esxiHost = $ESXiHostsHash[$esxiHostKey]
        PopulateStatsInfo $esxiHost
        AnonymizeEsxiData $esxiHost
        Add-DataNode "Hosts" $esxiHost
    }

    # Iterate over all the VMs
    foreach ($vm in $VMList) {
        PopulateStatsInfo $vm
        AnonymizeVmData $vm
        Add-DataNode "vms" $vm
    }
}

ProcessDatacenters 
ProcessClusters 
ProcessESXiHosts 
ProcessVirtualMachines 
ProcessStats 
GenerateJsonData

if ($script) {
    Write-Output "BEGIN_DATA_PARSE_SECTION"
    $allData | ConvertTo-Json -Depth 10 
}
else {
    $allData | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile
}

