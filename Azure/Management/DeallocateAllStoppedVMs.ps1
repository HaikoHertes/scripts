<#
    .DESCRIPTION
        This runbooks deallocates all stopped Azure VMs in all Ressource Groups that have the Tag "AutoDeallocate" set to "Yes" at the schedule of the runbook, i.e. once per hour.
        Attention: This need the Azure Automation modules being updated - take a look on this video: https://www.youtube.com/watch?v=D61XWOeN_w8&t=11s (08:30)
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2019/06/26
#>


# Login to Azure with AzureRunAsConnection
$connectionName = "AzureRunAsConnection" 
try
{
    # Get the connection "AzureRunAsConnection "
    $ServicePrincipalConnection=Get-AutomationConnection -Name $connectionName         
    
    "Logging into Azure using service principal connection $connectionName..."
    Login-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $ServicePrincipalConnection.TenantId `
        -ApplicationId $ServicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint 

}
catch {
    if (!$ServicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

# Get all VMs in all RGs
# Version 1 - Needs to use the Tag "AutoDeallocate"
[array]$VMs = Get-AzureRMVm -Status | `
# First, only get VMs with the needed tags set and being running
Where-Object {($PSItem.Tags.Keys -contains "AutoDeallocate") `
         -and ($PSItem.PowerState -eq "VM stopped")} | `
      # Next, find VMs that should get deallocated
      Where-Object {$PSItem.Tags.AutoDeallocate -eq "Yes"}
      
<#
# Version 2 - Deallocate all VMs without using the Tag "AutoDeallocate"
[array]$VMs = Get-AzureRMVm -Status | Where-Object {$PSItem.PowerState -eq "VM stopped"}
#>

# Iterate through VMs and deallocate them
ForEach ($VM in $VMs) 
{
    Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    Write-Output "Deallocating $($VM.Name)..."
    Stop-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force
}
