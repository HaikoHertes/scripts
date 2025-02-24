[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $SubId
)

$Connect = @()
$response = try {(Invoke-WebRequest -UseBasicParsing -Uri "https://management.azure.com/subscriptions/$($SubId)?api-version=2015-01-01" -ErrorAction Stop).BaseResponse} catch { $_.Exception.Response } 
$stringHeader = $response.Headers.ToString()
$TenantId = $stringHeader.SubString($stringHeader.IndexOf("login.windows.net")+18,36)
$Connect += Connect-AzAccount -TenantId $TenantId -SubscriptionId $SubId

# Show Tenant Name, Subscription Name and Subscription ID from $Connect
$Connect | ForEach-Object { 
    return [PSCustomObject]@{
        Tenant = $_.Context.Tenant.TenantId
        SubscriptionName = $_.Context.Subscription.Name
        SubscriptionId = $_.Context.Subscription.Id
    }
}