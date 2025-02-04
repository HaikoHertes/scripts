#Define the tenant you will use to register your machine as Arc device
$TenantId = "PUT-TENANT-ID-HERE"

#Define the subscription where you want to register your machine as Arc device
$Subscription = "PUT-SUBSCRIPTION-ID-HERE"

#Define the resource group where you want to register your machine as Arc device
$RG = "PUT-RESOURCE-GROUP-NAME-HERE"

#Define the region to use to register your server as Arc device
#Do not use spaces or capital letters when defining region
$Region = "westeurope"
# Be aware that the region being used for Arc must also be supported by Azure Stack HCI later!
# See https://learn.microsoft.com/en-us/azure/azure-local/concepts/system-requirements?tabs=azure-public#azure-requirements

$LoginWith = "ServicePrincipal" # Use "DeviceCode" for device code login, "Interactive" for interactive login, and "ServicePrincipal" for service principal login
$AppId= "PUT-APP-ID-HERE" # Only needed when using Service Principal login
$ClientSecret = "PUT-CLIENT-SECRET-HERE" # Only needed when using Service Principal login

$Action = "Onboarding" # Use "Onboarding" to onboard the machine to Arc, "Offboarding" to offboard the machine from Arc

#Define the proxy address if your Azure Local deployment accesses the internet via proxy
#If you do not use a proxy, comment out the line below
# $ProxyServer = "http://proxyaddress:port"

If($LoginWith -eq "DeviceCode") {
    Connect-AzAccount -SubscriptionId $Subscription -TenantId $TenantId -DeviceCode    
} elseif ($LoginWith -eq "ServicePrincipal") {
    $SecurePassword = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AppId, $SecurePassword
    Connect-AzAccount -ServicePrincipal -TenantId $TenantId -Credential $Credential
} else {
    #Login to your Azure account interactively
    Login-AzAccount -Subscription $Subscription -Tenant $TenantId
}


#Get the Access Token for the registration
$ARMtoken = (Get-AzAccessToken -WarningAction SilentlyContinue).Token

#Get the Account ID for the registration
$id = (Get-AzContext).Account.Id

If($Action -eq "Offboarding" ) {
    #Invoke the de-registration script depending on if a proxy is used or not
    If([string]::IsNullOrEmpty($ProxyServer)) {
        Remove-AzStackHciArcInitialization -SubscriptionID $Subscription -ResourceGroup $RG -TenantID $TenantId -Region $Region -Cloud "AzureCloud" -ArmAccessToken $ARMtoken -AccountID $id        
    } Else {
        Remove-AzStackHciArcInitialization -SubscriptionID $Subscription -ResourceGroup $RG -TenantID $TenantId -Region $Region -Cloud "AzureCloud" -ArmAccessToken $ARMtoken -AccountID $id -Proxy $ProxyServer
    }

} else { 
    #Invoke the registration script depending on if a proxy is used or not
    If([string]::IsNullOrEmpty($ProxyServer)) {
        Invoke-AzStackHciArcInitialization -SubscriptionID $Subscription -ResourceGroup $RG -TenantID $TenantId -Region $Region -Cloud "AzureCloud" -ArmAccessToken $ARMtoken -AccountID $id
    } Else {
        Invoke-AzStackHciArcInitialization -SubscriptionID $Subscription -ResourceGroup $RG -TenantID $TenantId -Region $Region -Cloud "AzureCloud" -ArmAccessToken $ARMtoken -AccountID $id -Proxy $ProxyServer
    }
}
