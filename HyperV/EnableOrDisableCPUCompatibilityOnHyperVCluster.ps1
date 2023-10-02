[CmdletBinding()]
param (
    # Put your Clusters FQDN or NetBIOS name here
    [Parameter(
        ValueFromPipelineByPropertyName = $true,
        Position = 0)]
    [String]
    $HyperVClusterName = "CLUSTER.DOMAIN.LOCAL",

    # Use "Enable" or "Disable" to set the CompatibilityForMigration feature
    [ValidateSet("Enable","Disable")]
    [String]
    $CpuCompatibilityMode = "Disable"
)

"Getting all VMs in Cluster..."
$AllVms = Get-VM –ComputerName (Get-ClusterNode –Cluster $HyperVClusterName)
If($AllVms.Count -lt 1)
{
    Throw "No VMs found in Cluster $HyperVClusterName!"
}
else {
    If($CpuCompatibilityMode -eq "Enable")
    {
        "Enabling CompatibilityForMigrationEnabled..."
        ForEach($VM in ($AllVMs | Where-Object {($_ | Get-VMProcessor).CompatibilityForMigrationEnabled -eq $false}))
        {
            "$($VM.VMName)..."
            $flagToStartVM = $false
            If($VM.State -ne "Off")
            {
                $flagToStartVM = $true
                $VM | Stop-VM
            }
            $VM | Set-VMProcessor -CompatibilityForMigrationEnabled $true
            If($flagToStartVM)
            {
                $VM | Start-VM
            }

        }
    }
    elseif($CpuCompatibilityMode -eq "Disable")
    {
        "Disabling CompatibilityForMigrationEnabled..."
        ForEach($VM in ($AllVMs | Where-Object {($_ | Get-VMProcessor).CompatibilityForMigrationEnabled -eq $true}))
        {
            "$($VM.VMName)..."
            $flagToStartVM = $false
            If($VM.State -ne "Off")
            {
                $flagToStartVM = $true
                $VM | Stop-VM
            }
            $VM | Set-VMProcessor -CompatibilityForMigrationEnabled $false
            If($flagToStartVM)
            {
                $VM | Start-VM
            }
        }
    }
    else
    {
        Throw "No or wrong value for CpuCompatibilityMode provided - use ""Enable"" or ""Disable"""
    }
    $AllVms = Get-VM –ComputerName (Get-ClusterNode –Cluster $HyperVClusterName)
    $AllVms | Select-Object ComputerName,VMName,@{label="CompatibilityForMigrationEnabled"; expression={($_ | Get-VMProcessor).CompatibilityForMigrationEnabled}}
}
