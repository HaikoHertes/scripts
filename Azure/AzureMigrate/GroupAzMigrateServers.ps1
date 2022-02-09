<#
    .SYNOPSIS

    Adds already discovered Servers in Azure Migrate into an assessment group.

    .DESCRIPTION
        
    Adds already discovered Servers in Azure Migrate into an assessment group via REST-Calls. If the group does not exist yet, it gets created.

    .EXAMPLE
        \GroupAzMigrateServers.ps1 `
            -SubscriptionId "123456-1c32-7890-a6bd-08154711faa" `
            -ResourceGroupName "RG-SomeRG" `
            -AzMigrateProjectName "SomeProject" `
            -AzMigrateGroupName "SomeGroup" `
            -ServerNames "SomeServer1","SomeServer2"
    .EXAMPLE
        \GroupAzMigrateServers.ps1 `
            -SubscriptionId "123456-1c32-7890-a6bd-08154711faa" `
            -ResourceGroupName "RG-SomeRG" `
            -AzMigrateProjectName "SomeProject" `
            -AzMigrateGroupName "SomeGroup" `
            -ServerNames ((Import-CSV -Path "C:\servers.csv" -Delimiter ";").Hostname)
                
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

[string]$SubscriptionId = "26655ce5-1c32-4693-a6bd-505410055faa"
[string]$ResourceGroupName = "RG-Demos"
[string]$AzMigrateProjectName = "DemoMigration"
[string]$AzMigrateGroupName = "NeueGruppe2"
[string[]]$ServerNames = ("SERVER4 - Mail","SERVER5 - Web")

try
{
    Connect-AzAccount -Subscription $SubscriptionId -WarningAction SilentlyContinue -ErrorAction Stop
}
catch
{
    write-output  $_.Exception.message;
    throw "Error connecting to Azure!"
}
Write-Debug "Login successfull!"

try {
    Set-AzContext -SubscriptionId $SubscriptionId -WarningAction SilentlyContinue -ErrorAction Stop
}
catch
{
    write-output  $_.Exception.message;
    throw "Error switching to Subscription $SubscriptionId!"
}
Write-Debug "Switching Subscription context successfull!"


$AssessmentProject = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects?api-version=2019-10-01"
If(($AssessmentProject | Measure-Object).Count -lt 1)
{
    throw "No Azure Microsoft.Migrate/assessmentProjects found in Resource Group $ResourceGroupName!"
}
else {
    $InternalAzMigrateProjectName = (($AssessmentProject | Where-Object {($_.Content | ConvertFrom-Json).Value.properties.assessmentSolutionId -like "*/Microsoft.Migrate/MigrateProjects/$AzMigrateProjectName/*"}).Content | ConvertFrom-Json).value.name
    Write-Debug "Assessment project $InternalAzMigrateProjectName found!"
}


$AllMachines = Invoke-AzRestmethod -Method GET -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/machines?api-version=2019-10-01"
$AllMachines = ($AllMachines.Content | ConvertFrom-Json).value
If($AllMachines.Count -lt 1)
{
    throw "No machines found in Assessment project $InternalAzMigrateProjectName!"
}
else {
    $RelevantMachines = $AllMachines | Where-Object {$_.Properties.displayName -in $ServerNames}
    Write-Debug "Found $($AllMachines.Count) total machines, from which $($RelevantMachines.Count) out of given $($ServerNames.Count) are relevant in Assessment project $InternalAzMigrateProjectName"
}

$Group = Invoke-AzRestmethod -Method GET -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/?api-version=2019-10-01"
If(($Group.Content | ConvertFrom-Json).name -notcontains $AzMigrateGroupName)
{
    Write-Debug "Azure Migrate Assessment Group $AzMigrateGroupName not found in given project - creating it!"
    $RESTPayload = "{
        'name': '$AzMigrateGroupName',
        'type': 'Microsoft.Migrate/assessmentprojects/groups',
        'properties': {
          'groupType': 'Default',
          'machineCount': 0,
          'assessments': [],
          'supportedAssessmentTypes': [
            'MachineAssessment'
          ],
          'areAssessmentsRunning': false    
        }
      }"
    $NewGroup = Invoke-AzRestmethod -Method PUT -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/?api-version=2019-10-01" -Payload $RESTPayload
    If($NewGroup.StatusCode -ne 200)
    {
        throw "Cannot create non-existing group $AzMigrateGroupName - aborting."
    }
}

$RESTPayload = "{
                    'properties': {
                        'machines': ['$(([string]($RelevantMachines.id)).Replace(" ","','"))'],
                        'operationType':'Add'
                    }
                }"
$Result = Invoke-AzRestMethod -Method POST `
                              -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/updateMachines?api-version=2019-10-01" `
                              -Payload $RESTPayload

If($Result.StatusCode -eq 200)
{
    Write-Host "Successfull!" -ForegroundColor "Green"
}
else {
    $Result.Content | ConvertFrom-Json
    ($Result.Content | ConvertFrom-Json).properties
    throw "Something went wrong - check details above"
    
}

   