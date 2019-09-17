# Put your Subscription Name here
$SubscriptionName = "Microsoft Azure Sponsorship"

### No need to change anything below here ###

Install-Module -Name Az -AllowClobber -Scope CurrentUser
Login-AzAccount
$SubID = (Get-AzSubscription -SubscriptionName $SubscriptionName).Id
Select-AzSubscription $SubId

function Get-Difference([string[]]$Array1, [string[]]$Array2)
{
    # Be carrefull when using this function for different purpose - it will eliminate duplicate entries
    $diff = [Collections.Generic.HashSet[string]]$Array1
    $diff.SymmetricExceptWith([Collections.Generic.HashSet[string]]$Array2)
    $diffArray = [string[]]$diff
    Return $diffArray
}

cls
# orphaned public IPs
Write-Host "Getting orphaned public IPs..." -ForegroundColor Green
$a = (Get-AzPublicIpAddress).Id.Where({ $_ -ne "" }) # this is to remove empty entries
$b = (Get-AzNetworkInterface).IpConfigurationsText |  ForEach-Object {(ConvertFrom-Json $_).PublicIpAddress.Id}
Get-Difference -Array1 $a -Array2 $b | Sort-Object -Unique | Where-Object {$_} # this is to remove empty entries

# orphaned NICs
Write-Host "Getting orphaned network interfaces..." -ForegroundColor Green
$a = (Get-AzNetworkInterface).Id
$b = (Get-AzVM).NetworkProfile.NetworkInterfaces.Id
Get-Difference -Array1 $a -Array2 $b | Sort-Object -Unique

# orphaned managed disks
Write-Host "Getting orphaned managed disks..." -ForegroundColor Green
$a = (Get-AzDisk).Id
$b = (Get-AzVm).StorageProfile.OsDisk.ManagedDisk.Id
$c = $b + (Get-AzVm).StorageProfile.DataDisks.ManagedDisk.Id
Get-Difference -Array1 $a -Array2 $c | Sort-Object -Unique

# not-in-use NSGs
Write-Host "Getting unused NSGs..." -ForegroundColor Green
$a = (Get-AzNetworkSecurityGroup).Id
# NSGs attached to Subnets
$b = (Get-AzVirtualNetwork).Subnets.NetworkSecurityGroup.Id
# NSGs attached to NICs
$c = $b + (Get-AzNetworkInterface).NetworkSecurityGroup.Id
Get-Difference -Array1 $a -Array2 $c | Sort-Object -Unique

