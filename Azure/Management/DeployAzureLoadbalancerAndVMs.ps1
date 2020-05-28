<#
    .DESCRIPTION
        This script deploys two Azure VMs in an Availability Set behind an Azure Load Balancer, together with the needed NSG and rules
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2020/05/28
#>


# Change this as needed
$SubscriptionID = "PUT-SUB-ID-HERE"
$RGName='RG-YourRGName'

$Location='westeurope'
$avSetName = "YourAvailabilitySet"
$LBName = "YourLoadBalancer"
$ipSKU = "Standard" # Change this to "Standard" if needed
$VNetName = "YourVNet"
$VM1Name = "VM1"
$VM2Name = "VM2"
$VMSize = "Standard_DS1_v2" # Change SKU if needed - get SKU names and prices from here https://azureprice.net/

#Login-AzAccount
Connect-AzAccount

Set-AzContext -SubscriptionId $SubscriptionID

New-AzResourceGroup `
   -Name $RGName `
   -Location $Location

$publicIp = New-AzPublicIpAddress `
 -ResourceGroupName $RGName `
 -Name "$($LBName)PublicIP" `
 -Location $Location `
 -AllocationMethod static `
 -SKU $ipSKU

 $feip = New-AzLoadBalancerFrontendIpConfig -Name 'FrontEndPool' -PublicIpAddress $publicIp
 
 $bepool = New-AzLoadBalancerBackendAddressPoolConfig -Name 'BackEndPool'

 $probe = New-AzLoadBalancerProbeConfig `
 -Name 'HealthProbe' `
 -Protocol Http -Port 80 `
 -RequestPath / -IntervalInSeconds 360 -ProbeCount 5

 $rule = New-AzLoadBalancerRuleConfig `
  -Name 'LoadBalancerRuleWeb' -Protocol Tcp `
  -Probe $probe -FrontendPort 80 -BackendPort 80 `
  -FrontendIpConfiguration $feip `
  -BackendAddressPool $bePool

### NAT Rules ###

<# remove this if you want to not use RDP over NAT on LB #>
$natrule1 = New-AzLoadBalancerInboundNatRuleConfig `
  -Name 'LoadBalancerNATRuleRDP1' `
  -FrontendIpConfiguration $feip `
  -Protocol tcp `
  -FrontendPort 33891 `
  -BackendPort 3389

<# remove this if you want to not use RDP over NAT on LB #>
$natrule2 = New-AzLoadBalancerInboundNatRuleConfig `
  -Name 'LoadBalancerNATRuleRDP2' `
  -FrontendIpConfiguration $feip `
  -Protocol tcp `
  -FrontendPort 33892 `
  -BackendPort 3389


$lb = New-AzLoadBalancer `
  -ResourceGroupName $RGName `
  -Name $LBName `
  -SKU $ipSKU `
  -Location $Location `
  -FrontendIpConfiguration $feip `
  -BackendAddressPool $bepool `
  -Probe $probe `
  -InboundNatRule $natrule1,$natrule2 <# remove this if you want to not use RDP over NAT on LB #>`
  -LoadBalancingRule $rule 
  

# Create subnet config
$subnetConfig = New-AzVirtualNetworkSubnetConfig `
  -Name "Default" `
  -AddressPrefix 10.0.2.0/24 # Change if needed
Write-Host -ForegroundColor Green "You can ignore the Warning about the breaking change..."

# Create the virtual network
$vnet = New-AzVirtualNetwork `
  -ResourceGroupName $RGName `
  -Location $Location `
  -Name $VNetName `
  -AddressPrefix 10.0.0.0/16 <# Change if needed#>`
  -Subnet $subnetConfig

<## Uncomment this, if you want to have public IPs on your VMs as well
$RdpPublicIP_1 = New-AzPublicIpAddress `
  -Name "$($VM1Name)PublicIP" `
  -ResourceGroupName $RgName `
  -Location $Location  `
  -SKU $ipSKU `
  -AllocationMethod static
 

$RdpPublicIP_2 = New-AzPublicIpAddress `
  -Name "$($VM2Name)PublicIP" `
  -ResourceGroupName $RgName `
  -Location $Location  `
  -SKU $ipSKU `
  -AllocationMethod static
##>

$rule1 = New-AzNetworkSecurityRuleConfig -Name 'YourNetworkSecurityGroupRuleHTTP' -Description 'Allow HTTP' `
  -Access Allow -Protocol Tcp -Direction Inbound -Priority 2000 `
  -SourceAddressPrefix Internet -SourcePortRange * `
  -DestinationAddressPrefix * -DestinationPortRange 80

<# remove this if you want to not use RDP#>
$rule2 = New-AzNetworkSecurityRuleConfig -Name 'YourNetworkSecurityGroupRuleRDP' -Description 'Allow RDP' `
  -Access Allow -Protocol Tcp -Direction Inbound -Priority 1000 `
  -SourceAddressPrefix Internet -SourcePortRange * `
  -DestinationAddressPrefix * -DestinationPortRange 3389

$nsg = New-AzNetworkSecurityGroup -ResourceGroupName $RgName -Location $Location `
-Name "$($VNetName)NSG" -SecurityRules $rule1,$rule2 # Remove rule2 here if needed

# Create NIC for VM1
$nicVM1 = New-AzNetworkInterface -ResourceGroupName $RGName -Location $Location `
  -Name "$($VM1Name)Nic" -LoadBalancerBackendAddressPool $bepool -NetworkSecurityGroup $nsg `
  -LoadBalancerInboundNatRule $natrule1 -Subnet $vnet.Subnets[0]

$nicVM2 = New-AzNetworkInterface -ResourceGroupName $RGName -Location $Location `
  -Name "$($VM2Name)Nic" -LoadBalancerBackendAddressPool $bepool -NetworkSecurityGroup $nsg `
  -LoadBalancerInboundNatRule $natrule2 -Subnet $vnet.Subnets[0]

$cred = Get-Credential -Message "Please enter Username and Password to be used for the new VMs!"

$AVSet = New-AzAvailabilitySet `
   -Location $Location `
   -Name $avSetName `
   -ResourceGroupName $RGName `
   -Sku aligned `
   -PlatformFaultDomainCount 2 `
   -PlatformUpdateDomainCount 3


# ############## VM1 ###############

# Create a virtual machine configuration
$vmConfig = New-AzVMConfig -VMName $VM1Name -VMSize $VMSize -AvailabilitySetID $AVSet.Id`
 | Set-AzVMOperatingSystem -Windows -ComputerName $VM1Name -Credential $cred `
 | Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-Datacenter -Version latest `
 | Add-AzVMNetworkInterface -Id $nicVM1.Id

# Create a virtual machine
$vm1 = New-AzVM -ResourceGroupName $RGName -Location $Location -VM $vmConfig

# ############## VM2 ###############

# Create a virtual machine configuration
$vmConfig = New-AzVMConfig -VMName $VM2Name -VMSize $VMSize -AvailabilitySetID $AVSet.Id `
 | Set-AzVMOperatingSystem -Windows -ComputerName $VM2Name -Credential $cred `
 | Set-AzVMSourceImage -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-Datacenter -Version latest `
 | Add-AzVMNetworkInterface -Id $nicVM2.Id

# Create a virtual machine
$vm2 = New-AzVM -ResourceGroupName $RGName -Location $Location -VM $vmConfig

Write-Host "Deployment startet - follow process using Azure portal..."
Write-Host "Load Balancers public IP address is $($publicIp.IpAddress)!"