[CmdletBinding()]
param (
    
    [String]
    $TenantId = "b9b25f83-56b0-4c03-8a95-717a9e63808b",

    [String]
    $SourceSubscriptionId = "1e79c102-26e2-45de-bc3f-779b1fb1f6f7",

    [String]
    $DestinationSubscriptionId = "20cc1a82-1123-48ec-bd89-7d03a7550be3",

    [String[]]
    $RGsToSkip = ("MorphoSysAG","AzureBackupRG_westeurope_1","CommVault_Backup","NetworkWatcherRG")

)


Write-Verbose "Connecting to Azure..."

try {
    Set-AzContext -TenantId $TenantId -WarningAction Stop > $null
    Write-Host "✔ Login" -ForegroundColor Green
}
#catch [Microsoft.Open.Azure.AD.CommonLibrary.AadNeedAuthenticationException] {
catch{    
    Write-Warning -Message "You're not connected. Connecting now."
    Connect-AzAccount -TenantId $TenantId -ErrorAction Break > $null
    Write-Host "✔ Login" -ForegroundColor Green
}

Write-Host "Gathering source resource groups and their RBAC assignments..."  -ForegroundColor Green
$RGsWithRBAC = @()
Set-AzContext -Tenant $TenantId -SubscriptionId $SourceSubscriptionId > $null
$AllRGs = Get-AzResourceGroup
ForEach($RG in $AllRGs)
{
    Write-Host "Resource Group: $($RG.ResourceGroupName)" -ForegroundColor Green
    If($RG.ResourceGroupName -in $RGsToSkip)        
    {
        Write-Host "RG is on the skip-list - skipping..." -ForegroundColor Yellow         
    }
    else {

        $RBACList = Get-AzRoleAssignment -ResourceGroupName ($RG.ResourceGroupName) | Where-Object {$_.Scope -eq $RG.ResourceId}

        $RGsWithRBAC += [PSCustomObject]@{
            ResourceGroup = $RG
            RoleAssignments = $RBACList
        }


        
    }
    #Read-Host "ENTER to proceed..."
}
Write-Host "###########################################################################" -ForegroundColor Green
Write-Host "Source Subscription: $((Get-AzContext).Subscription.Name)" -ForegroundColor Green
Set-AzContext -Tenant $TenantId -SubscriptionId $DestinationSubscriptionId > $null
Write-Host "Destination Subscription: $((Get-AzContext).Subscription.Name)" -ForegroundColor Green
Write-Host "Cloning RGs..." -ForegroundColor Green
Write-Host "###########################################################################" -ForegroundColor Green
ForEach($RGObject in $RGsWithRBAC)
{
    If((Get-AzResourceGroup -Name ($RGObject.ResourceGroup.ResourceGroupName) -Location ($RGObject.ResourceGroup.Location) -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
    {
        Write-Host "Resource Group ""$($RGObject.ResourceGroup.ResourceGroupName)"" already exists in destination subscription - skipping..." -ForegroundColor Yellow
    }
    else {
        New-AzResourceGroup -Name ($RGObject.ResourceGroup.ResourceGroupName) -Location ($RGObject.ResourceGroup.Location)
        ForEach($RBACEntry in $RGObject.RoleAssignments)
        {
            New-AzRoleAssignment -ResourceGroupName ($RGObject.ResourceGroup.ResourceGroupName) -RoleDefinitionName ($RBACEntry.RoleDefinitionName) -ObjectId ($RBACEntry.ObjectId)
        }
        Write-Host "Resource Group ""$($RGObject.ResourceGroup.ResourceGroupName)"" got created and roles assigned!" -ForegroundColor Green
    }
    #Read-Host "ENTER to proceed..."
}