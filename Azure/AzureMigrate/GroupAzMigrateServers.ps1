<#
    .DESCRIPTION
        tbd
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2022/02/08
#>

[CmdletBinding()]
param (
    [parameter(Mandatory=$true)]
    [string]
    $SubscriptionId,
    
    [parameter(Mandatory=$true)]
    [string]
    $ResourceGroupName,

    [parameter(Mandatory=$true)]
    [string]
    $AzMigrateProjectName,

    [parameter(Mandatory=$true)]
    [string]
    $AzMigrateGroupName,

    [parameter(Mandatory=$true)]
    [string[]]
    $ServerNames
)

[string]$SubscriptionId = "26655ce5-1c32-4693-a6bd-505410055faa"
[string]$ResourceGroupName = "RG-Demos"
[string]$AzMigrateProjectName = "DemoMigration"
[string]$AzMigrateGroupName = "NeueGruppe"
[string[]]$ServerNames = ("SERVER4 - Mail","SERVER5 - Web")

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

# Call:
<#
C:\Users\micro\.vscode\Repos\haikohertes_scripts\scripts\Azure\AzureMigrate\GroupAzMigrateServers.ps1 `
    -SubscriptionId "26655ce5-1c32-4693-a6bd-505410055faa" `
    -ResourceGroupName "RG-Demos" `
    -AzMigrateProjectName "DemoMigration" `
    -AzMigrateGroupName "NeueGruppe" `
    -ServerNames "SERVER4 - Mail","SERVER5 - Web"

#>    

   