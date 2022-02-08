<#
    .DESCRIPTION
        tbd - no error handling yet
    .EXAMPLE
        \GroupAzMigrateServers.ps1 `
            -SubscriptionId "123456-1c32-7890-a6bd-08154711faa" `
            -ResourceGroupName "RG-SomeRG" `
            -AzMigrateProjectName "SomeProject" `
            -AzMigrateGroupName "SomeGroup" `
            -ServerNames "SomeServer1","SomeServer2"
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2022/02/08
#>

[CmdletBinding()]
param (
    
    # Subscription ID of the Azure Migrate Project to use
    [parameter(Mandatory=$true)]
    [string]
    $SubscriptionId,
    
    # Resource Group name of the Azure Migrate Project to use
    [parameter(Mandatory=$true)]
    [string]
    $ResourceGroupName,

    # Name of the Azure Migrate Project to use (as defined by the user)
    [parameter(Mandatory=$true)]
    [string]
    $AzMigrateProjectName,

    # Name of the Azure Migrate Assessment group to use - must be preexisting
    [parameter(Mandatory=$true)]
    [string]
    $AzMigrateGroupName,

    # List of Servernames as used in Azure Migrate Assessment / Discovery to be added to the group
    [parameter(Mandatory=$true)]
    [string[]]
    $ServerNames
)


Connect-AzAccount -Subscription $SubscriptionId -WarningAction SilentlyContinue
Set-AzContext -SubscriptionId $SubscriptionId -WarningAction SilentlyContinue

$AssessmentProject = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects?api-version=2019-10-01"
$InternalAzMigrateProjectName = (($AssessmentProject | Where-Object {($_.Content | ConvertFrom-Json).Value.properties.assessmentSolutionId -like "*/Microsoft.Migrate/MigrateProjects/$AzMigrateProjectName/*"}).Content | ConvertFrom-Json).value.name
$AllMachines = Invoke-AzRestmethod -Method GET -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/machines?api-version=2019-10-01"
$AllMachines = ($AllMachines.Content | ConvertFrom-Json).value
$RelevantMachines = $AllMachines | Where-Object {$_.Properties.displayName -in $ServerNames}

$RESTPayload = "{'properties': {'machines': ['$(([string]($RelevantMachines.id)).Replace(" ","','"))'],'operationType':'Add'}}"

$Result = Invoke-AzRestMethod -Method POST `
                              -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/updateMachines?api-version=2019-10-01" `
                              -Payload $RESTPayload

If($Result.StatusCode -eq 200)
{
    Write-Host "Successfull!" -ForegroundColor "Green"
}
else {
    Write-Host "Something went wrong - check details:" -ForegroundColor "Red"
    $Result.Content | ConvertFrom-Json
    ($Result.Content | ConvertFrom-Json).properties
}

   