Set-MlnxDriverCoreSetting -RoceMode 1.0 -Confirm:$false

$pNIC1 = "10G_right"
$pNIC2 = "10G_left"

$vNIC1 = "vSMB1"
$vNIC2 = "vSMB2"

Remove-NetQosPolicy -Confirm:$False
Remove-NetQosTrafficClass -Confirm:$False
Disable-NetQosFlowControl -Priority 0,1,2,3,4,5,6,7

Get-NetAdapterQos -Name $vNIC1, $vNIC2 | Disable-NetAdapterQos
Get-NetAdapterRDMA -Name $vNIC1, $vNIC2 | Disable-NetAdapterRDMA
Get-NetAdapterQos -Name $pNIC1, $pNIC2 | Disable-NetAdapterQos
Get-NetAdapterRDMA -Name $pNIC1, $pNIC2 | Disable-NetAdapterRDMA


#Set-NetAdapterAdvancedProperty $pNIC1 -RegistryKeyword VlanID -RegistryValue "101"
#Set-NetAdapterAdvancedProperty $pNIC2 -RegistryKeyword VlanID -RegistryValue "101"
#Restart-NetAdapter $pNIC1,$pNIC2

Get-NetAdapterAdvancedProperty -Name $pNIC1,$pNIC2 | Where-Object {$_.RegistryKeyword -eq "VlanID"} | ft -AutoSize

Install-WindowsFeature Data-Center-Bridging

New-NetQosPolicy "Cluster" -Cluster -PriorityValue8021Action 7
New-NetQosTrafficClass "Cluster" -Priority 7 -BandwidthPercentage 2 -Algorithm ETS

New-NetQosPolicy "SMB" -NetDirectPortMatchCondition 445 -PriorityValue8021Action 3
Enable-NetQosFlowControl -priority 3
New-NetQosTrafficClass "SMB" -priority 3 -bandwidthpercentage 75 -algorithm ETS

Enable-NetAdapterQos -InterfaceAlias $pNIC1,$pNIC2

Set-NetQosDcbxSetting -InterfaceAlias $pNIC1 -Willing $False
Set-NetQosDcbxSetting -InterfaceAlias $pNIC2 -Willing $False

New-NetQosPolicy "DEFAULT" -Default -PriorityValue8021Action 0
Disable-NetQosFlowControl -priority 0,1,2,4,5,6,7

Enable-NetAdapterRdma $pNIC1,$pNIC2

Set-NetAdapterAdvancedProperty -Name $pNIC1 -RegistryKeyword VlanID -RegistryValue "0"
Set-NetAdapterAdvancedProperty -Name $pNIC2 -RegistryKeyword VlanID -RegistryValue "0"

Set-VMNetworkAdapterVlan -ManagementOS -Access -VlanId 101 -VMNetworkAdapterName $vNIC1
Set-VMNetworkAdapter -ManagementOS -Name $vNIC1 -IeeePriorityTag on
Enable-NetAdapterRdma $vNIC1

Set-VMNetworkAdapterVlan -ManagementOS -Access -VlanId 101 -VMNetworkAdapterName $vNIC2
Set-VMNetworkAdapter -ManagementOS -Name $vNIC2 -IeeePriorityTag on
Enable-NetAdapterRdma $vNIC2

Set-VMNetworkAdapterTeamMapping -ManagementOS -VMNetworkAdapterName $vNIC1 -PhysicalNetAdapterName $pNIC1
Set-VMNetworkAdapterTeamMapping -ManagementOS -VMNetworkAdapterName $vNIC2 -PhysicalNetAdapterName $pNIC2

# Enable-NetAdapterSriov $pNIC1,$pNIC2