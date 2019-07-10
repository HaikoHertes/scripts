<#
    .DESCRIPTION
        This runbooks shuts down all Azure VMs in all Ressource Groups that have the Tag "AutoShutdown" set to "Yes" at the UTC time given in "AutoShutdownTime" in the format "HH:mm:ss" and
        starts all Azure VMs in all Ressource Groups that have the Tag "AutoStartup" set to "Yes" at the UTC time given in "AutoStartupTime" in the format "HH:mm:ss".
        Attention: This need the Azure Automation modules being updated - take a look on this video: https://www.youtube.com/watch?v=D61XWOeN_w8&t=11s (08:30)
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2019/07/10
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
[array]$AllVms = Get-AzureRMVm -Status

[array]$VmsToStart = @()
[array]$VmsToStop = @()

# And here comes the ugly part - I know there is a shorter way for this, but this would become un-read-able for others...
$AllVms | ForEach-Object {
    #AutoShutdown AND AutoStartup as well as AutoShutdownTime AND AutoStartupTime set
    if(($PSItem.Tags.Keys -contains "AutoShutdown") -and ($PSItem.Tags.Keys -contains "AutoStartup") -and ($PSItem.Tags.Keys -contains "AutoShutdownTime") -and ($PSItem.Tags.Keys -contains "AutoStartupTime"))
    {
        #AutoShutdown == Yes and AutoStartup == Yes
        If(($PSItem.Tags.AutoShutdown -eq "Yes") -and ($PSItem.Tags.AutoStartup -eq "Yes"))
        {
            #AutoShutdownTime > AutoStartupTime
            if([datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null) -gt [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null))
            {
                #CurrentTime > AutoShutdownTime
                if($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null) -and ($PSItem.PowerState -eq "VM running"))
                {
                    $VmsToStop += $PSItem
                }
                #CurrentTime > AutoStartupTime
                elseif($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null) -and $PSItem.PowerState -ne "VM running")
                {
                    $VmsToStart += $PSItem
                }
            }
            #AutoShutdownTime < AutoStartupTime
            elseif([datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null) -lt [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null))
            {
                #CurrentTime > AutoStartupTime
                if($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null) -and $PSItem.PowerState -ne "VM running")
                {
                    $VmsToStart += $PSItem
                }
                #CurrentTime > AutoShutdownTime
                elseif($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null) -and $PSItem.PowerState -eq "VM running")
                {
                    $VmsToStop += $PSItem
                }    
            }
            #AutoShutdownTime == AutoStartupTime
            elseif([datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null) -eq [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null))
            {
                Write-Output "$($PSItem.Name) has AutoStartupTime == AutoShutdownTime!"
            }
        }
        #AutoShutdown == Yes, AutoStartup != Yes
        If(($PSItem.Tags.AutoShutdown -eq "Yes") -and ($PSItem.Tags.AutoStartup -ne "Yes"))
        {
            #CurrentTime > AutoShutdownTime
            if($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null) -and $PSItem.PowerState -eq "VM running")
            {
                $VmsToStop += $PSItem
            }
        }            
        #AutoShutdown != Yes, AutoStartup == Yes
        If(($PSItem.Tags.AutoShutdown -ne "Yes") -and ($PSItem.Tags.AutoStartup -eq "Yes"))
        {
            #CurrentTime > AutoStartupTime
            if($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null) -and $PSItem.PowerState -ne "VM running")
            {
                $VmsToStart += $PSItem
            }
        }
    }
    #Only AutoShutdown as well as AutoShutdownTime set
    elseif(($PSItem.Tags.Keys -contains "AutoShutdown") -and ($PSItem.Tags.Keys -contains "AutoShutdownTime"))
    {
        If(($PSItem.Tags.AutoShutdown -eq "Yes"))
        {
            #CurrentTime > AutoShutdownTime
            if($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoShutdownTime,'HH:mm:ss',$null) -and $PSItem.PowerState -eq "VM running")
            {
                $VmsToStop += $PSItem
            }
        } 
    }
    #Only AutoStartup as well as AutoStartupTime set
    elseif(($PSItem.Tags.Keys -contains "AutoStartup") -and ($PSItem.Tags.Keys -contains "AutoStartupTime"))
    {
        If(($PSItem.Tags.AutoStartup -eq "Yes"))
        {
            #CurrentTime > AutoStartupTime
            if($CurrentDateTimeUTC -ge [datetime]::ParseExact($PSItem.Tags.AutoStartupTime,'HH:mm:ss',$null) -and $PSItem.PowerState -ne "VM running")
            {
                $VmsToStart += $PSItem
            }
        }
    }
}

Write-Output "These VMs will get started:"
Write-Output "$($VmsToStart.Name)"
Write-Output "These VMs will get stopped:"
Write-Output "$($VmsToStop.Name)"

# Iterate through VmsToStop and shut them down
ForEach ($VM in $VmsToStop) 
{
    #Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    Write-Output "Shutting down: $($VM.Name) with given shutdown time $($VM.Tags.AutoShutdownTime) in current state $($VM.PowerState)..."
    Stop-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force
}

ForEach ($VM in $VmsToStart ) 
{
    #Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    Write-Output "Starting : $($VM.Name) with given startup time $($VM.Tags.AutoStartupTime) in current state $($VM.PowerState)..."
    Start-AzureRMVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName
}
