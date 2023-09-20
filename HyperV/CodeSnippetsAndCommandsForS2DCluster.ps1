$NIC1 = "10G_right"
$NIC2 = "10G_left"

#$NIC1 = "Ethernet"
#$NIC2 = "Ethernet 2"

Set-NetAdapterAdvancedProperty $NIC1 -RegistryKeyword VlanID -RegistryValue "101"
Set-NetAdapterAdvancedProperty $NIC2 -RegistryKeyword VlanID -RegistryValue "102"
Restart-NetAdapter $NIC1,$NIC2
Get-NetAdapterAdvancedProperty -Name $NIC1,$NIC2 | Where-Object {$_.RegistryKeyword -eq "VlanID"} | ft -AutoSize
#Test-NetConnection 192.168.6.111
#Test-NetConnection 192.168.6.211
#Read-Host "Proceed?"

# Step 3 - DCB
Install-WindowsFeature "Data-Center-Bridging"
Remove-NetQosTrafficClass
Remove-NetQosPolicy -Confirm:$False
New-NetQosPolicy "Cluster" -Cluster -PriorityValue8021Action 7
New-NetQosTrafficClass "Cluster" -Priority 7 -BandwidthPercentage 2 -Algorithm ETS

New-NetQosPolicy "SMB" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 5
#Enable-NetQosFlowControl -priority 5
New-NetQosTrafficClass "SMB" -priority 5 -bandwidthpercentage 50 -algorithm ETS
New-NetQosPolicy "SMB Direct" –NetDirectPort 445 –Priority 5

New-NetQosPolicy "Live Migration" –LiveMigration -PriorityValue8021Action 6
New-NetQosTrafficClass "Live Migration" -priority 6 -bandwidthpercentage 30 -algorithm ETS

New-NetQosPolicy "DEFAULT" -Default -PriorityValue8021Action 0

Enable-NetAdapterQos -InterfaceAlias $NIC1,$NIC2

Set-NetQosDcbxSetting -InterfaceAlias $NIC1 -Willing $False
Set-NetQosDcbxSetting -InterfaceAlias $NIC2 -Willing $False



Disable-NetQosFlowControl -priority 0,1,2,3,4,5,6,7
Enable-NetQosFlowControl -priority 5

Get-NetQosFlowControl
Get-NetAdapterQos -Name $NIC1,$NIC2
Read-Host "Proceed?"

Enable-NetAdapterRdma $NIC1,$NIC2
Get-SmbClientNetworkInterface
Read-Host "Proceed?"

Set-NetAdapterAdvancedProperty -Name $NIC1 -RegistryKeyword VlanID -RegistryValue "0"
Set-NetAdapterAdvancedProperty -Name $NIC2 -RegistryKeyword VlanID -RegistryValue "0"

Get-VMNetworkAdapter -ManagementOS
Set-VMNetworkAdapterVlan -ManagementOS -Access -VlanId 101 -VMNetworkAdapterName "vSMB1"
Set-VMNetworkAdapter -ManagementOS -Name "vSMB1" -IeeePriorityTag on
Set-VMNetworkAdapterVlan -ManagementOS -Access -VlanId 102 -VMNetworkAdapterName "vSMB2"
Set-VMNetworkAdapter -ManagementOS -Name "vSMB2" -IeeePriorityTag on
Enable-NetAdapterRdma "vSMB1","vSMB2"

# C:\TEST\Test-RDMA.PS1 -IfIndex 39 -IsRoCE $true -RemoteIpAddress 192.168.6.112 -PathToDiskspd C:\TEST\

# > If RoCE v2 is not necessary for routing purposes, RoCE v1 may give better performance (v2 supports using multiple subnets)
Set-MlnxDriverCoreSetting -RoceMode 1.0 -Confirm:$false

Enable-ClusterStorageSpacesDirect -Verbose

Get-PhysicalDisk -CanPool $True| Where-Object DeviceID -ne 0 | ForEach-Object {
    Add-PhysicalDisk -StoragePoolName "S2D on HVCLUSTER01" -PhysicalDisks $_ -Verbose
}
#Add-PhysicalDisk -StoragePool (Get-StoragePool "S2D on HVCLUSTER01") -PhysicalDisks (Get-PhysicalDisk | Where DeviceID -ne 0 | Where CanPool -eq $True) -Verbose

Get-StoragePool -IsPrimordial $False | Add-PhysicalDisk -PhysicalDisks (Get-PhysicalDisk -CanPool $True | Where-Object DeviceID -ne 0)


# Jumbo Frames / Packets
#Get-NetAdapterAdvancedProperty -Name "10G*" -DisplayName "Jumbo*" | Set-NetAdapterAdvancedProperty -RegistryValue "9014"
#Get-NetAdapterAdvancedProperty -Name "vSMB1","vSMB2" -DisplayName "Jumbo*" | Set-NetAdapterAdvancedProperty -RegistryValue "9014"
Get-NetAdapterAdvancedProperty -Name "10G*" -DisplayName "Jumbo*" | Set-NetAdapterAdvancedProperty -RegistryValue "4088"
Get-NetAdapterAdvancedProperty -Name "vSMB1","vSMB2" -DisplayName "Jumbo*" | Set-NetAdapterAdvancedProperty -RegistryValue "4088"