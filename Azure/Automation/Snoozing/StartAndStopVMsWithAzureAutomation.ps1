[CmdletBinding()]
param(
    [int]$ThrottleLimit = 8,
    [string]$AutoStartupTagName = "autostartup",
    [string]$AutoStartupTimeTagName = "autostartuptime",
    [string]$AutoStartupDaysTagName = "autostartupdays",
    [string]$AutoShutdownTagName = "autoshutdown",
    [string]$AutoShutdownTimeTagName = "autoshutdowntime",
    [string]$AutoShutdownDaysTagName = "autoshutdowndays"
)

<#
    .DESCRIPTION
        This runbooks shuts down all Azure VMs in all Ressource Groups that have the Tag "AUTOSHUTDOWN" set to "true" at the time given in "AUTOSHUTDOWNTIME" in the format "HH:mm" and
        starts all Azure VMs in all Ressource Groups that have the Tag "AUTOSTARTUP" set to "true" at the UTC time given in "AUTOSTARTUPTIME" in the format "HH:mm".
        
        Optional Tags to control days of execution:
        - "AUTOSTARTUPDAYS": Format "xoooooo" where x=execute, o=skip (Mon-Sun). Example: "xoooooo" = Monday only, "xxxxxxoo" = Mon-Fri
        - "AUTOSHUTDOWNDAYS": Same format as above. If not specified, action runs every day
        
        Attention: This need the Azure Automation modules being updated - take a look on this video: https://www.youtube.com/watch?v=D61XWOeN_w8&t=11s (08:30)
        The Script will only touch a VM if the given time to start / stop is less than an hour ago! (Otherwise we would run into strange behavior in certain situations)
    .NOTES
        AUTHOR: Haiko Hertes, SoftwareONE
                Microsoft Azure MVP & Azure Architect
        LASTEDIT: 2026/01/23 - Added parallel processing and day-of-week tags
#>

# For comparison, we need the current UTC time in Germany
#$CurrentDateTimeUTC = (Get-Date).ToUniversalTime()
$ScriptStartTime = Get-Date
$CurrentDateTimeGER = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,"W. Europe Standard Time")
"Starttime: $(([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,""W. Europe Standard Time"")).tostring(""HH:mm:ss""))"

# Function to check if current day matches the day pattern
# Pattern format: "xoooooo" = Mon-Sun, x=execute, o=skip
function Test-DayOfWeekMatch {
    param(
        [string]$DayPattern
    )
    
    if ([string]::IsNullOrWhiteSpace($DayPattern) -or $DayPattern.Length -ne 7) {
        return $true  # If pattern is invalid or not set, allow execution any day
    }
    
    $CurrentDay = [int][System.DayOfWeek]::([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,"W. Europe Standard Time").DayOfWeek)
    # Convert .NET DayOfWeek (Sunday=0) to our format (Monday=0), so we shift by 1
    $CurrentDay = ($CurrentDay + 6) % 7
    
    return $DayPattern[$CurrentDay] -eq 'x'
}

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
"Getting VMs from $($AllSubscriptions.Count) subscription(s) in parallel with ThrottleLimit=$ThrottleLimit..."

# Fetch VMs from all subscriptions in parallel
[array]$AllVms = @($AllSubscriptions | ForEach-Object -Parallel {
    $Sub = $_
    $Sub | Set-AzContext -WarningAction SilentlyContinue | Out-Null
    Get-AzVm -Status
} -ThrottleLimit $ThrottleLimit)

"Found $($AllVms.Count) VMs..."

# Get all VMs in all RGs

[array]$VmsToStart = @()
[array]$VmsToStop = @()

# Process VMs in parallel to determine which ones need to start/stop
"Processing $($AllVms.Count) VMs in parallel with ThrottleLimit=$ThrottleLimit..."

$VMActions = @($AllVms | ForEach-Object -Parallel {
    $VM = $_
    $VmToStart = $false
    $AutoStartupTagName = $Using:AutoStartupTagName
    $AutoStartupTimeTagName = $Using:AutoStartupTimeTagName
    $AutoStartupDaysTagName = $Using:AutoStartupDaysTagName
    $AutoShutdownTagName = $Using:AutoShutdownTagName
    $AutoShutdownTimeTagName = $Using:AutoShutdownTimeTagName
    $AutoShutdownDaysTagName = $Using:AutoShutdownDaysTagName

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
            
            # Do we need to startup the VM now / was the startup time set between now and one hour ago?
            $CurrentDateTimeGER = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,"W. Europe Standard Time")
            If(
                (Test-DayOfWeekMatch -DayPattern $DayPattern) -and
                $CurrentDateTimeGER -ge [datetime]::ParseExact($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoStartupTimeTagName.toLower()})"],'HH:mm',$null) -and 
                $CurrentDateTimeGER.AddHours(-1) -le [datetime]::ParseExact($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoStartupTimeTagName.toLower()})"],'HH:mm',$null) -and 
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
            $CurrentDateTimeGER = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,"W. Europe Standard Time")
            If(
                (Test-DayOfWeekMatch -DayPattern $DayPattern) -and
                $CurrentDateTimeGER -ge [datetime]::ParseExact($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoShutdownTimeTagName.toLower()})"],'HH:mm',$null) -and 
                $CurrentDateTimeGER.AddHours(-1) -le [datetime]::ParseExact($VM.Tags["$($VM.Tags.Keys | Where-Object {$_.toLower() -ieq $AutoShutdownTimeTagName.toLower()})"],'HH:mm',$null) -and 
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
    $StartupTimeTag = $VM.Tags.Keys | Where-Object {$_.toLower() -ieq "autostartuptime"}
    $StartupTime = if ($StartupTimeTag) { $VM.Tags[$StartupTimeTag] } else { "N/A" }
    Write-Output "Starting : $($VM.Name) with given startup time $StartupTime in current state $($VM.PowerState)..."

    $SubId = $VM.Id.Split("/")[2] # This is the Subscription Id as part of
    $Context = Get-AzContext
    If($Context.Subscription.Id -ne $SubId)
    {
        Set-AzContext -SubscriptionId $SubId -WarningAction SilentlyContinue | Out-Null
    }
    $Jobs += Start-AzVm -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -AsJob
}

# Only wait if there are jobs to wait for
if ($Jobs.Count -gt 0) {
    "Waiting for all $($Jobs.Count) VM operations to complete (max 120 seconds)..."
    $Jobs | Wait-Job -Timeout 120 | Out-Null
    "VM operations completed!"
    
    # Display job results
    foreach ($Job in $Jobs) {
        $Result = $Job | Receive-Job -ErrorAction SilentlyContinue
        if ($Result) {
            Write-Output "Job $($Job.Name) result: $($Result -join '; ')"
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
"Total script runtime: $($ScriptRuntime.Hours):$($ScriptRuntime.Minutes):$($ScriptRuntime.Seconds)"
"Endtime: $(([System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::Now,""W. Europe Standard Time"")).tostring(""HH:mm:ss""))"