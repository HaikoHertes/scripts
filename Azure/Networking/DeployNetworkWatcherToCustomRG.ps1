ForEach($region in ("westeurope","northeurope","germanywestcentral"))
{
	New-AzNetworkWatcher -Name "NetworkWatcher_$region" -ResourceGroupName "RG-NetworkWatcher" -Location $region
}