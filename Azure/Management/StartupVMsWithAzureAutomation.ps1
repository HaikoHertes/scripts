<#
    .DESCRIPTION
        This runbooks starts all Azure VMs in all Ressource Groups that have the Tag "AutoStartup" set to "Yes" at the UTC time given in "AutoStartupTime" in the format "HH:mm:ss".
        Attention: This need the Azure Automation modules being updated - take a look on this video: https://www.youtube.com/watch?v=D61XWOeN_w8&t=11s

    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2019/06/18
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

# For comparison, we need the current UTC time
$CurrentDateTimeUTC = (Get-Date).ToUniversalTime()

# Get all VMs in all RGs
[array]$VMs = Get-AzureRMVm -Status | `
# First, only get VMs with the needed tags set and being running
Where-Object {($PSItem.Tags.Keys -contains "AutoStartup") `
         -and ($PSItem.Tags.Keys -contains "AutoStartupTime") `
         -and (($PSItem.PowerState -eq "VM deallocated") -or ($PSItem.PowerState -eq "VM stopped"))} | `
      # Next, find VMs that should shut down and have the time being over for this   
      Where-Object {($PSItem.Tags.AutoStartup -eq "Yes") `
               -and ($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null))}

# Iterate through VMs and shut them down
ForEach ($VM in $VMs) 
{
    Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    Write-Output "Starting : $($VM.Name) with given startup time $($VM.Tags.AutoStartupTime)..."
    Start-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName
}
