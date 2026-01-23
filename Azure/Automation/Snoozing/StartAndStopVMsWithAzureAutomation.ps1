<#
    .DESCRIPTION
        This runbooks shuts down all Azure VMs in all Ressource Groups that have the Tag "AUTOSHUTDOWN" set to "true" at the time given in "AUTOSHUTDOWNTIME" in the format "HH:mm" and
        starts all Azure VMs in all Ressource Groups that have the Tag "AUTOSTARTUP" set to "true" at the UTC time given in "AUTOSTARTUPTIME" in the format "HH:mm".
        
        Optional Tags to control days of execution:
        - "AUTOSTARTUPDAYS": Format "xoooooo" where x=execute, o=skip (Mon-Sun). Example: "xoooooo" = Monday only, "xxxxxxoo" = Mon-Fri
        - "AUTOSHUTDOWNDAYS": Same format as above. If not specified, action runs every day
        
        Attention: This need the Azure Automation modules being updated - take a look on this video: https://www.youtube.com/watch?v=D61XWOeN_w8&t=11s (08:30)
        The Script will only touch a VM if the given time to start / stop is less than an hour ago! (Otherwise we would run into strange behavior in certain situations)
    .PARAMETER ThrottleLimit
        Maximum number of VMs to process in parallel (default: 8)
    .PARAMETER MaxRetries
        Maximum number of retry attempts for failed start operations (default: 3)
    .PARAMETER StartupGracePeriod
        Grace period in minutes for startup - VMs will be started if their startup time is within +/- N minutes from now (default: 59)
        This allows for schedule delays and ensures startups within the grace period window
    .PARAMETER AutoStartupTagName
        Name of the tag that enables VM startup (default: autostartup)
    .PARAMETER AutoStartupTimeTagName
        Name of the tag containing the startup time in HH:mm format (default: autostartuptime)
    .PARAMETER AutoStartupDaysTagName
        Name of the tag controlling which days startup executes in format "xoooooo" Mon-Sun (default: autostartupdays)
    .PARAMETER AutoShutdownTagName
        Name of the tag that enables VM shutdown (default: autoshutdown)
    .PARAMETER AutoShutdownTimeTagName
        Name of the tag containing the shutdown time in HH:mm format (default: autoshutdowntime)
    .PARAMETER AutoShutdownDaysTagName
        Name of the tag controlling which days shutdown executes in format "xoooooo" Mon-Sun (default: autoshutdowndays)
    .PARAMETER TimeZone
        Time zone ID to use for time comparisons (default: "W. Europe Standard Time")
        Use [System.TimeZoneInfo]::GetSystemTimeZones() to list available time zones
    .PARAMETER FireAndForget
        If $true, the script will submit VM start/stop operations and exit immediately without waiting for completion (default: $false)
        Use this in Azure Automation to minimize script runtime and reduce costs. Operations will complete in the background.
    .NOTES
        AUTHOR: Haiko Hertes, SoftwareONE
                Microsoft Azure MVP & Azure Architect
        LASTEDIT: 2026/01/23
                Added parallel processing, day-of-week tags, Tags as Parameters, MaxRetries parameter, TZ as Parameter, Grace period for startup
                Script was tested using PowerShell 7.4 within Azure Automation
#>

[CmdletBinding()]
param(
    [int]$ThrottleLimit = 8,
    [int]$MaxRetries = 3,
    [int]$StartupGracePeriod = 59,
    [string]$AutoStartupTagName = "autostartup",
    [string]$AutoStartupTimeTagName = "autostartuptime",
    [string]$AutoStartupDaysTagName = "autostartupdays",
    [string]$AutoShutdownTagName = "autoshutdown",
    [string]$AutoShutdownTimeTagName = "autoshutdowntime",
    [string]$AutoShutdownDaysTagName = "autoshutdowndays",
    [string]$TimeZone = "W. Europe Standard Time",
    [bool]$FireAndForget = $false
)


# Verify that the specified timezone exists
try {
    [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone) | Out-Null
}
catch {
    Write-Error "The specified TimeZone '$TimeZone' does not exist. Use [System.TimeZoneInfo]::GetSystemTimeZones() to list available time zones."
    throw $_
}

# For comparison, we need the current time in the specified timezone
#$CurrentDateTimeUTC = (Get-Date).ToUniversalTime()
$ScriptStartTime = Get-Date
$CurrentDateTimeInGivenTZ = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,$TimeZone)
"Starttime: $(([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,$TimeZone)).tostring(""HH:mm:ss""))"

# Login to Azure using system-assigned managed identity
try
{
    "Logging into Azure using system assigned managed identity..."
    Connect-AzAccount -Identity -WarningAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
}
catch
{
    Write-Error -Message $_.Exception
    throw $_.Exception
}

$AllSubscriptions = Get-AzSubscription
"Getting VMs from $($AllSubscriptions.Count) subscription(s)..."

# Fetch VMs from all subscriptions (sequentially since parallel runspaces lose authentication context)
[array]$AllVms = @()
foreach ($Sub in $AllSubscriptions) {
    $Sub | Set-AzContext -WarningAction SilentlyContinue | Out-Null
    $AllVms += Get-AzVm -Status
}

"Found $($AllVms.Count) VMs..."

# Get all VMs in all RGs

[array]$VmsToStart = @()
[array]$VmsToStop = @()

# Process VMs in parallel to determine which ones need to start/stop
"Processing $($AllVms.Count) VMs in parallel with ThrottleLimit=$ThrottleLimit..."

$VMActions = @($AllVms | ForEach-Object -Parallel {
    # Define the function inside the parallel block so it's available in this runspace
    function Test-DayOfWeekMatch {
        param(
            [string]$DayPattern,
            [string]$TimeZoneId
        )
        if ([string]::IsNullOrWhiteSpace($DayPattern) -or $DayPattern.Length -ne 7) {
            return $true
        }
        $CurrentDay = [int][System.DayOfWeek]::([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,$TimeZoneId).DayOfWeek)
        $CurrentDay = ($CurrentDay + 6) % 7
        return $DayPattern[$CurrentDay] -eq 'x'
    }
    
    $VM = $_
    $VmToStart = $false
    $AutoStartupTagName = $Using:AutoStartupTagName
    $AutoStartupTimeTagName = $Using:AutoStartupTimeTagName
    $AutoStartupDaysTagName = $Using:AutoStartupDaysTagName
    $AutoShutdownTagName = $Using:AutoShutdownTagName
    $AutoShutdownTimeTagName = $Using:AutoShutdownTimeTagName
    $AutoShutdownDaysTagName = $Using:AutoShutdownDaysTagName
    $StartupGracePeriod = $Using:StartupGracePeriod
    $TimeZoneId = $Using:TimeZone

    # Does the VM has Startup Tags?
    if(($VM.Tags.Keys -icontains $AutoStartupTagName) -and ($VM.Tags.Keys -icontains $AutoStartupTimeTagName))
    {
        # Is the Startup Tag set to true?
        If($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoStartupTagName.toLower()})"] -eq "true")
        {
            # Check day-of-week pattern if specified
            $DayPattern = $VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoStartupDaysTagName.toLower()}
            if ($DayPattern) {
                $DayPattern = $VM.Tags[$DayPattern]
            }
            
            # Do we need to startup the VM now / is the startup time within 1 hour back and StartupGracePeriod forward?
            $CurrentDateTimeInGivenTZ = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,$TimeZoneId)
            $StartupTimeValue = [datetime]::ParseExact($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoStartupTimeTagName.toLower()})"],'HH:mm',$null)
            
            If(
                (Test-DayOfWeekMatch -DayPattern $DayPattern -TimeZoneId $TimeZoneId) -and
                $CurrentDateTimeInGivenTZ.AddHours(-1) -le $StartupTimeValue -and 
                $StartupTimeValue -le $CurrentDateTimeInGivenTZ.AddMinutes($StartupGracePeriod) -and 
                $VM.PowerState -ne "VM running"
               )
            {
                $VmToStart = $true
                [PSCustomObject]@{ Action = 'Start'; VM = $VM }
            }
        }
    }
    # Does the VM has Shutdown Tags and is not planned for startup (we consider startup to have higher priority)?
    if(($VM.Tags.Keys -icontains $AutoShutdownTagName) -and ($VM.Tags.Keys -icontains $AutoShutdownTimeTagName) -and (!$VmToStart))
    {
        # Is the Shutdown Tag set to true?
        If($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoShutdownTagName.toLower()})"] -eq "true")
        {
            # Check day-of-week pattern if specified
            $DayPattern = $VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoShutdownDaysTagName.toLower()}
            if ($DayPattern) {
                $DayPattern = $VM.Tags[$DayPattern]
            }
            
            # Do we need to shutdown the VM now / was the shutdown time set between now and one hour ago?
            $CurrentDateTimeInGivenTZ = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,$TimeZoneId)
            If(
                (Test-DayOfWeekMatch -DayPattern $DayPattern -TimeZoneId $TimeZoneId) -and
                $CurrentDateTimeInGivenTZ -ge [datetime]::ParseExact($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoShutdownTimeTagName.toLower()})"],'HH:mm',$null) -and 
                $CurrentDateTimeInGivenTZ.AddHours(-1) -le [datetime]::ParseExact($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoShutdownTimeTagName.toLower()})"],'HH:mm',$null) -and 
                $VM.PowerState -eq "VM running"
            )
            {
                [PSCustomObject]@{ Action = 'Stop'; VM = $VM }
            }
        }
    }
} -ThrottleLimit $ThrottleLimit)

# Distribute results into appropriate arrays
foreach ($Action in $VMActions) {
    if ($Action.Action -eq 'Start') {
        $VmsToStart += $Action.VM
    } else {
        $VmsToStop += $Action.VM
    }
}

Write-Output "These VMs will get started:"
Write-Output "$($VmsToStart.Name)"
Write-Output "These VMs will get stopped:"
Write-Output "$($VmsToStop.Name)"

$Jobs = @()

# Process both shutdown and startup in parallel
# Iterate through VmsToStop and shut them down
ForEach ($VM in ($VmsToStop | Sort-Object Id)) 
{
    #Write-Output "Current UTC time: $((Get-Date).ToUniversalTime())"
    $ShutdownTimeTag = $VM.Tags.Keys | Where-Object {$_.toLower() -ieq "autoshutdowntime"}
    $ShutdownTime = if ($ShutdownTimeTag) { $VM.Tags[$ShutdownTimeTag] } else { "N/A" }
    Write-Output "Shutting down: $($VM.Name) with given shutdown time $ShutdownTime in current state $($VM.PowerState)..."
    
    $SubId = $VM.Id.Split("/")[2] # This is the Subscription Id as part of the VMs resource ID
    $Context = Get-AzContext
    If($Context.Subscription.Id -ne $SubId)
    {
        Set-AzContext -SubscriptionId $SubId -WarningAction SilentlyContinue | Out-Null
    }
    $Jobs += Stop-AzVm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -AsJob
}

ForEach ($VM in ($VmsToStart | Sort-Object Id) ) 
{
    $StartupTimeTag = $VM.Tags.Keys | Where-Object {$_.toLower() -ieq "autostartuptime"}
    $StartupTime = if ($StartupTimeTag) { $VM.Tags[$StartupTimeTag] } else { "N/A" }
    Write-Output "Starting : $($VM.Name) with given startup time $StartupTime in current state $($VM.PowerState)..."

    $SubId = $VM.Id.Split("/")[2] # This is the Subscription Id as part of the VMs resource ID
    $Context = Get-AzContext
    If($Context.Subscription.Id -ne $SubId)
    {
        Set-AzContext -SubscriptionId $SubId -WarningAction SilentlyContinue | Out-Null
    }
    
    # Retry logic for start operations (up to MaxRetries attempts with 60 second wait between retries)
    $RetryCount = 0
    $StartJobCreated = $false
    
    while ($RetryCount -lt $MaxRetries -and -not $StartJobCreated) {
        try {
            $Jobs += Start-AzVm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -AsJob -ErrorAction Stop
            $StartJobCreated = $true
        }
        catch {
            $RetryCount++
            if ($RetryCount -lt $MaxRetries) {
                Write-Output "  Warning: Failed to start $($VM.Name). Retrying in 60 seconds (Attempt $RetryCount of $MaxRetries)..."
                Start-Sleep -Seconds 60
            } else {
                Write-Output "  Error: Failed to start $($VM.Name) after $MaxRetries attempts. Skipping."
            }
        }
    }
}

# Only wait if there are jobs to wait for (unless FireAndForget mode is enabled)
if ($Jobs.Count -gt 0) {
    if ($FireAndForget) {
        "FireAndForget mode enabled: $($Jobs.Count) VM operation(s) submitted. Script exiting without waiting for completion."
    }
    else {
        "Waiting for all $($Jobs.Count) VM operations to complete (max 120 seconds)..."
        $Jobs | Wait-Job -Timeout 120 | Out-Null
        "VM operations completed!"
        
        # Display job results - show status and any errors
        foreach ($Job in $Jobs) {
            $JobStatus = if ($Job.State -eq 'Completed') { '✓ Success' } else { '✗ ' + $Job.State }
            Write-Output "  $($Job.Name): $JobStatus"
            
            # Capture any errors from the job
            if ($Job.Error) {
                foreach ($ErrorRecord in $Job.Error) {
                    Write-Output "    Error: $($ErrorRecord.Exception.Message)"
                }
            }
        }
    }
}
else {
    "No VMs require action at this time."
}

# Calculate and display statistics
$ScriptEndTime = Get-Date
$ScriptRuntime = $ScriptEndTime - $ScriptStartTime
$VMsTouched = $VmsToStart.Count + $VmsToStop.Count

"" # Empty line for readability
"=== SCRIPT EXECUTION SUMMARY ==="
"Subscriptions processed: $($AllSubscriptions.Count)"
"Total VMs found: $($AllVms.Count)"
"VMs touched (Start/Stop): $VMsTouched"
"  - VMs started: $($VmsToStart.Count)"
"  - VMs stopped: $($VmsToStop.Count)"
"Total script runtime: $('{0:hh\:mm\:ss}' -f $ScriptRuntime)"
"Endtime: $(([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,$TimeZone)).tostring(""HH:mm:ss""))"