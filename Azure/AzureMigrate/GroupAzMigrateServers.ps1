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

# Trying to switch Context into right Subscription
try 
{
    $context = Get-AzContext -ListAvailable  | Where-Object {$_.Subscription -eq $SubsciptionId}
}
catch
{
    write-output  $_.Exception.message;
    throw "Error getting current context - aborting"
}

If($context -eq $null)
{
    # No context found for needed Subscription - login to Azure
    try
    {
        Connect-AzAccount -Subscription $SubscriptionId -WarningAction SilentlyContinue -ErrorAction Stop
        Write-Debug "Loging in to Azure successfull!"
    }
    catch {
        write-output  $_.Exception.message;
        throw "Error connecting to Azure - aborting"
    }
}

try {
    # Setting Context
    Set-AzContext -SubscriptionId $SubscriptionId -WarningAction SilentlyContinue -ErrorAction Stop
    Write-Debug "Switching Subscription context successfull!"    
}
catch {
    # write-output  $_.Exception.message;
    # Context might be outdated - so we need to re-login
    try
    {
        Connect-AzAccount -Subscription $SubscriptionId -WarningAction SilentlyContinue -ErrorAction Stop
        Write-Debug "Loging in to Azure successfull!"
    }
    catch {
        write-output  $_.Exception.message;
        throw "Error connecting to Azure - aborting"
    }
}
    

# Getting the "internal" Name of the Azure Migrate Assessment project (which is not the same as the Migrate Project itself)
$AssessmentProject = Invoke-AzRestMethod -Method GET -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects?api-version=2019-10-01"
If(($AssessmentProject | Measure-Object).Count -lt 1)
{
    throw "No Azure Microsoft.Migrate/assessmentProjects found in Resource Group $ResourceGroupName!"
}
else {
    $InternalAzMigrateProjectName = (($AssessmentProject | Where-Object {($_.Content | ConvertFrom-Json).Value.properties.assessmentSolutionId -like "*/Microsoft.Migrate/MigrateProjects/$AzMigrateProjectName/*"}).Content | ConvertFrom-Json).value.name
    Write-Debug "Assessment project $InternalAzMigrateProjectName found!"
}

# Getting the IDs of the Azure Migrate discovered systems - API will only return 100 per call, so we need to iterate here
Set-AzContext -Subscription $SubscriptionId -WarningAction SilentlyContinue -ErrorAction Stop
$AllMachines = @()
$nextLink = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/machines?api-version=2019-10-01"
Write-Debug "Getting all machines from Assessment project $InternalAzMigrateProjectName..."
do {
    $APIResult = Invoke-AzRestmethod -Method GET -Path $nextLink
    $nextLink = ($APIResult.Content | ConvertFrom-JSON).nextLink
    if ($nextLink -ne $null)
    {
        $nextLink = $nextLink.Replace("https://management.azure.com","") # Invoke-AzRestmethod expects an Path starting with /subscriptions... instead of https://management.azure.com, but the response gives a nextPageLink including this
    }   
    $AllMachines += $APIResult
} while (
    $nextLink -ne $null
)

$AllMachines = ($AllMachines.Content | ConvertFrom-Json).value
If($AllMachines.Count -lt 1)
{
    throw "No machines found in Assessment project $InternalAzMigrateProjectName!"
}
else {
    $RelevantMachines = $AllMachines | Where-Object {$_.Properties.displayName -in $ServerNames}
    Write-Debug "Found $($AllMachines.Count) total machines, from which $($RelevantMachines.Count) out of given $($ServerNames.Count) are relevant in Assessment project $InternalAzMigrateProjectName"
}


# Searching for the Group
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
    # Creating the group as it is not existing yet
    $NewGroup = Invoke-AzRestmethod -Method PUT -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/?api-version=2019-10-01" -Payload $RESTPayload
    If($NewGroup.StatusCode -ne 200)
    {
        # Retrying once...
        Write-Debug "1st Error - Retrying to create group once..."
        $NewGroup = Invoke-AzRestmethod -Method PUT -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/?api-version=2019-10-01" -Payload $RESTPayload
        If($NewGroup.StatusCode -ne 200)
        {
            throw "Cannot create non-existing group $AzMigrateGroupName - aborting."
        }            
    }
}

# Adding the found systems to the group in batches of 50 servers each
$BatchSize = 50
for($i=0; $i -lt $RelevantMachines.Count; $i+=$BatchSize)
{
    Write-Debug "Adding $($BatchSize) machines to group $AzMigrateGroupName - Current Batch is $i..."
    $RESTPayload = "{
                        'properties': {
                            'machines': ['$(([string](($RelevantMachines | Select-Object -Skip $i -First $BatchSize).id)).Replace(" ","','"))'],
                            'operationType':'Add'
                        }
                    }"
    $Result = Invoke-AzRestMethod -Method POST `
                                -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/updateMachines?api-version=2019-10-01" `
                                -Payload $RESTPayload

    If($Result.StatusCode -eq 200)
    {
        Write-Debug "Successfull!"
    }
    else {
        # $Result.Content | ConvertFrom-Json
        # ($Result.Content | ConvertFrom-Json).properties

        #Retrying once
        Write-Debug "1st Error - Retrying batch once..."
        $Result = Invoke-AzRestMethod -Method POST `
                                -Path "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Migrate/assessmentProjects/$InternalAzMigrateProjectName/groups/$AzMigrateGroupName/updateMachines?api-version=2019-10-01" `
                                -Payload $RESTPayload

        If($Result.StatusCode -eq 200)
        {
            Write-Debug "Successfull!"
        }
        else {
            # For now, we are just skipping this batch...
            Write-Debug "2nd Error - Skipping current batch..."
            
            # throw "Something went wrong - check details above"
        }
    }
}  