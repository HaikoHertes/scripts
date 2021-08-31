Connect-AzAccount

$RuntimeQuery = 'Heartbeat | where TimeGenerated > ago(30d)
| summarize heartbeats_per_hour=count() by bin(TimeGenerated, 1h), ResourceId=tolower(ResourceId)
| extend state_per_hour=iff(heartbeats_per_hour>0, true, false)
| summarize total_running_hours=countif(state_per_hour==true) by ResourceId
| sort by total_running_hours'

$AllSubscriptions = Get-AzSubscription

$AllLogWorkspaces = @()
$AllVms = @()

ForEach($Sub in $AllSubscriptions)
{
    $Sub | Set-AzContext -WarningAction SilentlyContinue
    $AllLogWorkspaces += Get-AzOperationalInsightsWorkspace
    $AllVms += Get-AzVm -Status
}

If($AllLogWorkspaces.Count -gt 1)
{
    $UnionString = "union Heartbeat"
    ForEach($LAW in $AllLogWorkspaces)
    {
        $UnionString += ", workspace(""$($LAW.CustomerId)"").Heartbeat"
    }
    $UnionString += " |"
    $RuntimeQuery = $RuntimeQuery.Replace("Heartbeat |",$UnionString)
}

$RuntimeResult = (Invoke-AzOperationalInsightsQuery -Workspace ($AllLogWorkspaces[0]) -Query $RuntimeQuery).Results

$VMResults = @()
ForEach($VM in $AllVms)
{
    $VMResults += [PSCustomObject]@{
        VMName = $VM.Name
        RG = $VM.ResourceGroupName
        Location = $VM.Location
        Status = $VM.PowerState
        Runtime = [math]::Max(0,[int](($RuntimeResult | Where-Object {$_.ResourceId -eq $VM.Id}).total_running_hours))
    }
}

$VMResults | Sort-Object RG,VMName | Out-GridView

