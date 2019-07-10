<#
    .DESCRIPTION
        This runbooks shuts down all Azure VMs in all Ressource Groups that have the Tag "AutoShutdown" set to "Yes" at the UTC time given in "AutoShutdownTime" in the format "HH:mm:ss".
        Attention: This need the Azure Automation modules being updated - take a look on this video: https://www.youtube.com/watch?v=D61XWOeN_w8&t=11s (08:30)
        Recommondation: Use this Script instead: StartAndStopVMsWithAzureAutomation.ps1 (same Repo)

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
Where-Object {($PSItem.Tags.Keys -contains "AutoShutdown") `
         -and ($PSItem.Tags.Keys -contains "AutoShutdownTime") `
         -and ($PSItem.PowerState -eq "VM running")} | `
      # Next, find VMs that should shut down and have the time being over for this   
      Where-Object {($PSItem.Tags.AutoShutdown -eq "Yes") `
               -and ($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null))}

# Iterate through VMs and shut them down
ForEach ($VM in $VMs) 
{
    Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    Write-Output "Shutting down: $($VM.Name) with given shutdown time $($VM.Tags.AutoShutdownTime)..."
    Stop-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force
}
