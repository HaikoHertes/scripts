$CustomRoleID = "/subscriptions/26655ce5-1c32-4693-a6bd-505410055faa/providers/Microsoft.Authorization/roleDefinitions/e8445876-04bb-4076-8424-741a94102187"
$PrincipalID = "6d156e8a-1c90-4f85-b7f9-6a4328a78207"
$PrincipalType = "Group" # User or Group
$GUID1 = "d7ac398c-fef5-48e8-a6d7-4fe9f8d2308c"
$GUID2 = "e1b929f2-cc8b-4c64-b154-9d02135620f1"
$SubscriptionID = "26655ce5-1c32-4693-a6bd-505410055faa"
$ResourceGroupName = "rg-loggingandmonitoring"
$WorkspaceName = "demoworkspace-log"
$TableName = "AppServiceHTTPLogs"

$JsonRequestBody = "{
    'requests': [
        {
            ""content"": {
                ""Id"": ""$GUID1"",
                ""Properties"": {
                    ""PrincipalId"": ""$PrincipalID"",
                    ""PrincipalType"": ""$PrincipalType"",
                    ""RoleDefinitionId"": ""$CustomRoleID"",
                    ""Scope"": ""/subscriptions/$SubscriptionID/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/Tables/$TableName"",
                    ""Condition"": null,
                    ""ConditionVersion"": null
                }
            },
            ""httpMethod"": ""PUT"",
            ""name"": ""$GUID2"",
            ""requestHeaderDetails"": {
                ""commandName"": ""Microsoft_Azure_AD.""
            },
            ""url"": ""/subscriptions/$SubscriptionID/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/Tables/$TableName/providers/Microsoft.Authorization/roleAssignments/$GUID1?api-version=2020-04-01-preview""
        }
    ]
}"

#Connect-AzAccount
Invoke-AzRestMethod -Uri "https://management.azure.com/batch?api-version=2020-06-01" -Payload $JsonRequestBody
#Invoke-AzRestMethod -Path "/subscriptions/$SubscriptionID/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/Tables/$TableName/providers/Microsoft.Authorization/roleAssignments/$GUID1?api-version=2020-04-01" -Method "PUT" -Payload $JsonRequestBody
Invoke-AzRestMethod -SubscriptionId $SubscriptionID -ResourceGroupName $ResourceGroupName -ResourceProviderName "Microsoft.OperationalInsights" -ResourceType "workspaces" -Name $WorkspaceName -ApiVersion "2020-04-01-preview" -Method "PUT" -Payload $JsonRequestBody


$azContext = Set-AzContext -Subscription $SubscriptionID
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}

# Invoke the REST API
$restUri = 'https://management.azure.com/batch?api-version=2020-06-01'
$response = Invoke-RestMethod -Uri $restUri -Method PUT -Headers $authHeader -Body $JsonRequestBody