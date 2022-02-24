<#
    .SYNOPSIS

    Enables Diagnostic Settings to write Metrics into Log Analytics Workspace

    .DESCRIPTION
        
    tbd

    .EXAMPLE
         tbd
    .EXAMPLE
        tbd
                
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2022/02/24
#>

[CmdletBinding()]
param (
    
    # Name of the Diagnostic Settings
    [string]
    $DiagnosticSettingsName = "Send-Metrics-to-LogAnalytics",

    # Subscription ID of the target Log Analytics Workspace
    [parameter(Mandatory=$true)]
    [string]
    $WorkspaceSub,

    # Resource Group Name of the target Log Analytics Workspace
    [parameter(Mandatory=$true)]
    [string]
    $WorkspaceRG,

    # Name of the target Log Analytics Workspace
    [parameter(Mandatory=$true)]
    [string]
    $WorkspaceName,

    # Should we skip a resource that already has ANY diagnostic settings?
    [bool]
    $SkipIfExisting = $true,

    # Subscription-ID(s) of Subscription to apply this on, leave empty to use all available subscriptions
    [string[]]
    $SubscriptionId,

    # Should we enable the diagnostic settings for VMs?
    [bool]
    $EnableForVMs = $true,

    # Should we enable the diagnostic settings for Azure SQL Databases and Pools?
    [bool]
    $EnableForAzSql = $true,

    # Should we enable the diagnostic settings for Azure SQL Managed Instances?
    [bool]
    $EnableForAzSqlMI = $false, #nothing to be done here yet

    # Should we enable the diagnostic settings for App Service Plans?
    [bool]
    $EnableForAppServicePlans = $true,

    [bool]
    $SkipLogin = $false

)

If(!$SkipLogin)
{
    Clear-AzContext -Scope Process

    # Login to Azure
    try
    {
        Connect-AzAccount -WarningAction SilentlyContinue -ErrorAction Stop
    }
    catch
    {
        write-output  $_.Exception.message;
        throw "Error connecting to Azure!"
    }
    Write-Debug "Login successfull!"

    # Switching Context into right Tenant and Subscription
    try {
        Set-AzContext -SubscriptionId $WorkspaceSub -WarningAction SilentlyContinue -ErrorAction Stop
    }
    catch
    {
        write-output  $_.Exception.message;
        throw "Error switching to Subscription $SubscriptionId!"
    }
    Write-Debug "Switching Subscription context successfull!"

}

$TenantId = (Get-AzContext).Tenant.Id


If(![string]::IsNullOrEmpty($SubscriptionId))
{
    # Subscription set is limited due to parameter
    $AllSubscriptions = Get-AzSubscription -TenantId $TenantId | Where-Object {$_.Id -in $SubscriptionId}
    "Using just these Subscriptions:"
    $AllSubscriptions | Select-Object Name,Id
}
else
{
    # Use all visible subscriptions
    $AllSubscriptions = Get-AzSubscription -TenantId $TenantId
    "Using all Subscriptions. Total count is $(($AllSubscriptions | Measure-Object).Count)"
}

$Workspace = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $WorkspaceRG -Name $WorkspaceName -WarningAction SilentlyContinue)
If(($Workspace | Measure-Object).Count -ne 1)
{
    Throw "The given Log Analytics Workspace could not be found or their is multiple of them!"
}
else
{
    $WorkspaceId = $Workspace.CustomerId.Guid
    $WorkspaceResId = $Workspace.ResourceId
    $WorkspaceKey = (Get-AzOperationalInsightsWorkspaceSharedKey -ResourceGroupName $WorkspaceRG -Name $WorkspaceName -WarningAction SilentlyContinue).PrimarySharedKey
    $WorkspacePublicSettings = @{"workspaceId" = "$WorkspaceId"}
    $WorkspaceProtectedSettings = @{"workspaceKey" = "$WorkspaceKey"}
}

"Running through all Subscriptions to check / put the settings..."
ForEach($Subscription in $AllSubscriptions)
{
    "Using Subscription $($Subscription.Name) ($($Subscription.Id)) now..."
    Set-AzContext -Subscription $Subscription -WarningAction SilentlyContinue | Out-Null
    If($EnableForVMs)
    {
        "Taking care of the VMs now..."
        $NexExtensions = @()
        ForEach($VM in (Get-AzVM -Status | Where-Object PowerState -like "*running*"))
        {
            $Extensions = (Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name)
            If((($Extensions.ExtensionType -contains "MicrosoftMonitoringAgent") -or 
                ($Extensions.ExtensionType -contains "OmsAgentForLinux"))
            )
            {
                "VM $($VM.Name) has the right Agent installed"
                If(!$SkipIfExisting)
                {
                    "Installing MMA..."
                    $NexExtensions += Set-AzVMExtension -ExtensionName "MicrosoftMonitoringAgent" `
                        -ResourceGroupName $VM.ResourceGroupName `
                        -VMName $VM.Name `
                        -Publisher "Microsoft.EnterpriseCloud.Monitoring" `
                        -ExtensionType "MicrosoftMonitoringAgent" `
                        -TypeHandlerVersion 1.0 `
                        -Settings $WorkspacePublicSettings `
                        -ProtectedSettings $WorkspaceProtectedSettings `
                        -Location $VM.Location `
                        -NoWait

                }
            }
            else {
                "VM $($VM.Name) is missing the right Agent"
                "Installing MMA..."
                $NexExtensions += Set-AzVMExtension -ExtensionName "MicrosoftMonitoringAgent" `
                    -ResourceGroupName $VM.ResourceGroupName `
                    -VMName $VM.Name `
                    -Publisher "Microsoft.EnterpriseCloud.Monitoring" `
                    -ExtensionType "MicrosoftMonitoringAgent" `
                    -TypeHandlerVersion 1.0 `
                    -Settings $WorkspacePublicSettings `
                    -ProtectedSettings $WorkspaceProtectedSettings `
                    -Location $VM.Location `
                    -NoWait
            }

        }
    }

    If($EnableForAzSql)
    {
        "Taking care of Azure SQL DBs now..."
        $SqlServers = Get-AzSqlServer
        $AllAzureSqlDBs = @()
        $AllAzureSqlElasticPools = @()
        ForEach($Server in $SqlServers)
        {
            $AllAzureSqlDBs += Get-AzSqlDatabase -ServerName $Server.ServerName -ResourceGroupName $Server.ResourceGroupName -WarningAction SilentlyContinue
            $AllAzureSqlElasticPools += Get-AzSqlElasticPool -ServerName $Server.ServerName -ResourceGroupName $Server.ResourceGroupName -WarningAction SilentlyContinue
        }

        ForEach($SQLDB in ($AllAzureSqlDBs | Where-Object DatabaseName -ne "master"))
        {
            $DiagSettings = Get-AzDiagnosticSetting -ResourceId $SQLDB.ResourceId -WarningAction SilentlyContinue
            If((($DiagSettings.Metrics | Where-Object Category -eq "Basic").Enabled -notcontains "true") -or
            (!$SkipIfExisting))
            {
                "SQL Database $($SQLDB.DatabaseName) is either missing Diagnostic Settings or Skipping is disabled. Adding Diagnostic Settings now..."

                Set-AzDiagnosticSetting -ResourceId ($SQLDB.ResourceId) `
                        -Name $DiagnosticSettingsName `
                        -WorkspaceId $WorkspaceResId `
                        -EnableMetrics $true `
                        -MetricCategory "Basic" `
                        -WarningAction SilentlyContinue `
                        -ErrorAction Inquire
                
            }
            else
            {
                "SQL Database $($SQLDB.DatabaseName) already has some Diagnostic Settings for Basic Metrics - Skipping."
            }
        }

        ForEach($SQLPool in $AllAzureSqlElasticPools)
        {
            $DiagSettings = Get-AzDiagnosticSetting -ResourceId $SQLPool.ResourceId -WarningAction SilentlyContinue
            If((($DiagSettings.Metrics | Where-Object Category -eq "Basic").Enabled -notcontains "true") -or
            (!$SkipIfExisting))
            {
                "SQL ELastic Pool $($SQLPool.DatabaseName) is either missing Diagnostic Settings or Skipping is disabled. Adding Diagnostic Settings now..."

                Set-AzDiagnosticSetting -ResourceId ($SQLPool.ResourceId) `
                        -Name $DiagnosticSettingsName `
                        -WorkspaceId $WorkspaceResId `
                        -EnableMetrics $true `
                        -MetricCategory "Basic" `
                        -WarningAction SilentlyContinue `
                        -ErrorAction Inquire
                
            }
            else
            {
                "SQL ELastic Pool $($SQLPool.DatabaseName) already has some Diagnostic Settings for Basic Metrics - Skipping."
            }
        }
    }

    If($EnableForAzSqlMI)
    {
        "Taking care of Azure SQL Managed Instances now..."
        # No content yet as not needed for now
    }

    If($EnableForAppServicePlans)
    {
        "Taking care of App Service Plans now..."

        ForEach($AppServicePlan in (Get-AzAppServicePlan))
        {
            $DiagSettings = Get-AzDiagnosticSetting -ResourceId $AppServicePlan.Id -WarningAction SilentlyContinue
            If((($DiagSettings.Metrics | Where-Object Category -eq "AllMetrics").Enabled -notcontains "true") -or
            (!$SkipIfExisting))
            {
                "App Service Plan $($AppServicePlan.Name) is either missing Diagnostic Settings or Skipping is disabled. Adding Diagnostic Settings now..."

                Set-AzDiagnosticSetting -ResourceId ($AppServicePlan.Id) `
                        -Name $DiagnosticSettingsName `
                        -WorkspaceId $WorkspaceResId `
                        -EnableMetrics $true `
                        -MetricCategory "AllMetrics" `
                        -WarningAction SilentlyContinue `
                        -ErrorAction Inquire
                
            }
            else
            {
                "App Service Plan $($AppServicePlan.Name) already has some Diagnostic Settings for Basic AllMetrics - Skipping."
            }
        }
    }
}