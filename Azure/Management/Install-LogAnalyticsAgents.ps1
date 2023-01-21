Connect-AzAccount -Subscription "9e321b26-01c4-4b44-bb68-3e6ba770b5b5"
Set-AzContext -Subscription "9e321b26-01c4-4b44-bb68-3e6ba770b5b5"

Set-AzVMExtension -Name AzureMonitorWindowsAgent -ExtensionType AzureMonitorWindowsAgent -Publisher Microsoft.Azure.Monitor -ResourceGroupName "RG-AgentTests" -VMName "AMA" -Location "westeurope" -EnableAutomaticUpgrade $true -TypeHandlerVersion  "1.10"




$PublicSettings = @{"workspaceId" = "eb1bc48e-dae1-4a26-86a3-1a1b70a44853"}
$ProtectedSettings = @{"workspaceKey" = "RrojZIb3EoIy1igxlGLxxy2Vw4YBx6LdHCoYGdJXsrwL6P3Chu55mUGJumCVRlY5QO4NxN4a6xJmmZQ4sWoatQ=="}

Set-AzVMExtension -ExtensionName "MicrosoftMonitoringAgent" `
    -ResourceGroupName "RG-AgentTests" `
    -VMName "MMA" `
    -Publisher "Microsoft.EnterpriseCloud.Monitoring" `
    -ExtensionType "MicrosoftMonitoringAgent" `
    -TypeHandlerVersion 1.0 `
    -Settings $PublicSettings `
    -ProtectedSettings $ProtectedSettings `
    -Location westeurope