<#
    .DESCRIPTION
        This runbooks shuts down all Azure VMs in all Ressource Groups that have the Tag "AUTOSHUTDOWN" set to "true" at the time given in "AUTOSHUTDOWNTIME" in the format "HH:mm" and
        starts all Azure VMs in all Ressource Groups that have the Tag "AUTOSTARTUP" set to "true" at the UTC time given in "AUTOSTARTUPTIME" in the format "HH:mm".
        Attention: This need the Azure Automation modules being updated - take a look on this video: https://www.youtube.com/watch?v=D61XWOeN_w8&t=11s (08:30)
        The Script will only touch a VM if the given time to start / stop is less than an hour ago! (Otherwise we would run into strange behavior in certain situations)
    .NOTES
        AUTHOR: Haiko Hertes, SoftwareONE
                Microsoft Azure MVP & Azure Architect
        LASTEDIT: 2021/02/17
#>

# For comparison, we need the current UTC time in Germany
#$CurrentDateTimeUTC = (Get-Date).ToUniversalTime()
$CurrentDateTimeGER = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,"W. Europe Standard Time")
"Starttime: $(([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,""W. Europe Standard Time"")).tostring(""HH:mm:ss""))"

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

[array]$VmsToStart = @()
[array]$VmsToStop = @()

# And here comes the ugly part - I know there is a shorter way for this, but this would become un-read-able for others...
$AllVms | ForEach-Object {

    #"We are handling VM $($PSItem.Name) now"
    #"VM has these Tags:"
    #"$($PSItem.Tags.Keys)"

    $VmToStart = $false

    # Does the VM has Startup Tags?
    if(($PSItem.Tags.Keys -icontains "autostartup") -and ($PSItem.Tags.Keys -icontains "autostartuptime"))
    {
        #"VM has Startup Tags"
        # Is the Startup Tag set to true?
        If($PSItem.Tags["$($PSItem.Tags.Keys | Where {$_.toLower() -ieq "autostartup"})"] -eq "true")
        {
            #"VM hast autostartup set to true"
            # Do we need to startup the VM now / was the startup time set between now and one hour ago?
            If(
                $CurrentDateTimeGER -ge [datetime]::ParseExact($PSItem.Tags["$($PSItem.Tags.Keys | Where {$_.toLower() -ieq "autostartuptime"})"],'HH:mm',$null) -and 
                $CurrentDateTimeGER.AddHours(-1) -le [datetime]::ParseExact($PSItem.Tags["$($PSItem.Tags.Keys | Where {$_.toLower() -ieq "autostartuptime"})"],'HH:mm',$null) -and 
                $PSItem.PowerState -ne "VM running"
               )
            {
                $VmToStart = $true
                $VmsToStart += $PSItem
            }
        }
    }
    # Does the VM has Shutdown Tags and is not planned for startup (we consider startup to have higher priority)?
    if(($PSItem.Tags.Keys -icontains "autoshutdown") -and ($PSItem.Tags.Keys -icontains "autoshutdowntime") -and (!$VmToStart))
    {
        #"VM has Shutdown Tags"
        # Is the Shutdown Tag set to true?
        If($PSItem.Tags["$($PSItem.Tags.Keys | Where {$_.toLower() -ieq "autoshutdown"})"] -eq "true")
        {
            #"VM hast autoshutdown set to true"
            # Do we need to shutdown the VM now / was the shutdown time set between now and one hour ago?
            If(
            $CurrentDateTimeGER -ge [datetime]::ParseExact($PSItem.Tags["$($PSItem.Tags.Keys | Where {$_.toLower() -ieq "autoshutdowntime"})"],'HH:mm',$null) -and 
            $CurrentDateTimeGER.AddHours(-1) -le [datetime]::ParseExact($PSItem.Tags["$($PSItem.Tags.Keys | Where {$_.toLower() -ieq "autoshutdowntime"})"],'HH:mm',$null) -and 
            $PSItem.PowerState -eq "VM running"
            )
            {
                $VmsToStop += $PSItem
            }
        }
    }
}

Write-Output "These VMs will get started:"
Write-Output "$($VmsToStart.Name)"
Write-Output "These VMs will get stopped:"
Write-Output "$($VmsToStop.Name)"

$Jobs = @()

# Iterate through VmsToStop and shut them down
ForEach ($VM in ($VmsToStop | Sort-Object Id)) 
{
    #Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    Write-Output "Shutting down: $($VM.Name) with given shutdown time $($VM.Tags["$($VM.Tags.Keys | Where {$_.toLower() -ieq "autoshutdowntime"})"]) in current state $($VM.PowerState)..."
    
    $SubId = $VM.Id.Split("/")[2] # This is the Subscription Id as part of
    $Context = Get-AzContext
    If($Context.Subscription.Id -ne $SubId)
    {
        Set-AzContext -SubscriptionId $SubId -WarningAction SilentlyContinue | Out-Null
    }
    $Jobs += Stop-AzVm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -AsJob
}

ForEach ($VM in ($VmsToStart | Sort-Object Id) ) 
{
    #Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    Write-Output "Starting : $($VM.Name) with given startup time $($VM.Tags["$($VM.Tags.Keys | Where {$_.toLower() -ieq "autostartuptime"})"]) in current state $($VM.PowerState)..."

    $SubId = $VM.Id.Split("/")[2] # This is the Subscription Id as part of
    $Context = Get-AzContext
    If($Context.Subscription.Id -ne $SubId)
    {
        Set-AzContext -SubscriptionId $SubId -WarningAction SilentlyContinue | Out-Null
    }
    $Jobs += Start-AzVm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -AsJob
}

"Waiting for all Jobs to complete..."
$Jobs | Wait-Job -Timeout 120
"Jobs completed!"
$Jobs

"Endtime: $(([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,""W. Europe Standard Time"")).tostring(""HH:mm:ss""))"