[CmdletBinding()]
param (
    [Parameter()]
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


Set-AzContext -Tenant $TenantId -SubscriptionId $SourceSubscriptionId > $null
$AllRGs = Get-AzResourceGroup
ForEach($RG in $AllRGs)
{
    "Resource Group: $($RG.ResourceGroupName)"        
    If($RG.ResourceGroupName -in $RGsToSkip)        
    {
        "RG is on the skip-list - skipping..."            
    }
    else {
        Set-AzContext -Tenant $TenantId -SubscriptionId $SourceSubscriptionId > $null
        "Source: $((Get-AzContext).Subscription.Name)"

        $RBACList = Get-AzRoleAssignment -ResourceGroupName ($RG.ResourceGroupName) | Where-Object {$_.Scope -eq $RG.ResourceId}
        Set-AzContext -Tenant $TenantId -SubscriptionId $DestinationSubscriptionId > $null
        "Destination: $((Get-AzContext).Subscription.Name)"
        If((Get-AzResourceGroup -Name ($RG.ResourceGroupName) -Location ($RG.Location) -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
        {
            "Resource Group ""$($RG.ResourceGroupName)"" already exists in destination subscription - skipping..."
        }
        else {
            New-AzResourceGroup -Name ($RG.ResourceGroupName) -Location ($RG.Location)
            ForEach($RBACEntry in $RBACList)
            {
                New-AzRoleAssignment -ResourceGroupName ($RG.ResourceGroupName) -RoleDefinitionName ($RBACEntry.RoleDefinitionName) -ObjectId ($RBACEntry.ObjectId)
            }
            "Resource Group ""$($RG.ResourceGroupName)"" got created and roles assigned!"
        }
    }
    Read-Host "ENTER to proceed..."
}