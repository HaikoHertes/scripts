<#
    .DESCRIPTION
        This runbooks deallocates all stopped Azure VMs in all Ressource Groups that have the Tag "AutoDeallocate" set to "true" at the schedule of the runbook, i.e. once per hour.
    .NOTES
        AUTHOR: Haiko Hertes, SoftwareONE
                Microsoft MVP & Azure Architect
        LASTEDIT: 2021/02/17
#>

# Login to Azure using system-assigned managed identity
try
{
    "Logging into Azure using system assigned managed identity..."
    Connect-AzAccount -Identity
}
catch
{
    Write-Error -Message $_.Exception
    throw $_.Exception
}

$AllSubscriptions = Get-AzSubscription
[array]$AllVms = @()
ForEach($Sub in $AllSubscriptions)
{
    $Sub | Set-AzContext -WarningAction SilentlyContinue | out-null
    $AllVms += Get-AzVm -Status
}

"Found $($AllVms.Count) VMs..."

# Get all VMs in all RGs
[array]$VMs = $AllVms | `
# First, only get VMs with the needed tags set and being running
Where-Object {($PSItem.Tags.Keys -icontains "autodeallocate") `
         -and ($PSItem.PowerState -eq "VM stopped")} | `
      # Next, find VMs that should get deallocated
      Where-Object { $PSItem.Tags["$($PSItem.Tags.Keys | Where {$_.toLower() -ieq "autodeallocate"})"] -eq "true"}

# Iterate through VMs and deallocate them
$Jobs = @()
ForEach ($VM in ($VMs | Sort-Object Id)) 
{
    Write-Output "Deallocating $($VM.Name)..."
    $SubId = $VM.Id.Split("/")[2] # This is the Subscription Id as part of
    $Context = Get-AzContext
    If($Context.Subscription.Id -ne $SubId)
    {
        Set-AzContext -SubscriptionId $SubId -WarningAction SilentlyContinue | Out-Null
    }
    $Jobs += Stop-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -AsJob
}

"Waiting for all Jobs to complete..."
$Jobs | Wait-Job -Timeout 120
"Jobs completed!"