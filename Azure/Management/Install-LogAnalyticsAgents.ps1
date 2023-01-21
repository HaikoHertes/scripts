Connect-AzAccount -Subscription "SUB_ID_HERE"
Set-AzContext -Subscription "SUB_ID_HERE"

Set-AzVMExtension -Name AzureMonitorWindowsAgent -ExtensionType AzureMonitorWindowsAgent -Publisher Microsoft.Azure.Monitor -ResourceGroupName "RG-AgentTests" -VMName "AMA" -Location "westeurope" -EnableAutomaticUpgrade $true -TypeHandlerVersion  "1.10"




$PublicSettings = @{"workspaceId" = "WORKSPACE_ID_HERE"}
$ProtectedSettings = @{"workspaceKey" = "WORKSPACE_KEY_HERE"}

Set-AzVMExtension -ExtensionName "MicrosoftMonitoringAgent" `
    -ResourceGroupName "RG-AgentTests" `
    -VMName "MMA" `
    -Publisher "Microsoft.EnterpriseCloud.Monitoring" `
    -ExtensionType "MicrosoftMonitoringAgent" `
    -TypeHandlerVersion 1.0 `
    -Settings $PublicSettings `
    -ProtectedSettings $ProtectedSettings `
    -Location westeurope