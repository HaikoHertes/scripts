<#
    .SYNOPSIS
    Adds Network Watchers into custom defined Resource Groups for each given location and Subscription.
    .DESCRIPTION
        
    Usually, Network Watcher will be created in some Azure-provided Resource Group. 
	As the naming might not fit your scheme, you can use this script to define a custom Resource Group. 
	It will be created as well if not existing.

    .EXAMPLE
        .\DeployNetworkWatcherToCustomRG.ps1 `
            -regionsToUse "westeurope","northeurope"
            -SubscriptionsToUse "Sub1","Sub2" `
            -ResourceGroupNameToUse "RG-NetworkWatcher"
                
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2022/03/08
#>

[CmdletBinding()]
param (
	[string[]]
	$regionsToUse = ("westeurope","northeurope","germanywestcentral"),

	[parameter(Mandatory=$true)]
	[string[]]
	$SubscriptionsToUse, # ("PT_SUB_NAMES_HERE","OR_USE_SUB_IDS")

	[string]
	$ResourceGroupNameToUse = "RG-NetworkWatcher"
)

Clear-AzContext -Scope Process

# Login to Azure
try
{
	Connect-AzAccount -WarningAction SilentlyContinue -ErrorAction Stop
}
catch
{
	write-output  $_.Exception.message;
	throw "Error connecting to Azure!"
}
Write-Debug "Login successfull!"

$AllSubscriptions = Get-AzSubscription -WarningAction SilentlyContinue
$SubscriptionObjectsToUse = @()
ForEach($Sub in $SubscriptionsToUse)
{
	$SubscriptionObjectsToUse += $AllSubscriptions | Where-Object {($_.name -eq $Sub) -or ($_.Id -eq $Sub)}
}

ForEach($SubscriptionObject in $SubscriptionObjectsToUse)
{
	try {
		Set-AzContext -SubscriptionId $SubscriptionObject.Id -WarningAction SilentlyContinue -ErrorAction Stop
	}
	catch
	{
		write-output  $_.Exception.message;
		throw "Error switching to Subscription $($SubscriptionObject.Name) ($($SubscriptionObject.Id))!"
	}
	Write-Debug "Switching Subscription context successfull!"

	ForEach($region in $regionsToUse)
	{
		If((Get-AzResourceGroup -Name $ResourceGroupNameToUse | Measure-Object).Count -lt 1)
		{
			Write-Debug "Resource Group $ResourceGroupNameToUse not existing - creating it."
			New-AzResourceGroup -Name $ResourceGroupNameToUse -Location $region
		}
		Write-Debug "Adding Network Watcher for Location $region."
		New-AzNetworkWatcher -Name "NetworkWatcher_$region" -ResourceGroupName $ResourceGroupNameToUse -Location $region
	}
}