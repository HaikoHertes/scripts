# Policies with more than one Parameter

$PolicyName = "Append a tag and its value to resource groups"
$Policy = Get-AzPolicyDefinition -BuiltIn | Where-Object {$_.Properties.DisplayName -eq $PolicyName}
$Scope = Get-AzManagementGroup | where DisplayName -eq "hertes.net"

$TagName = "Owner"
$TagValue = "Unknown"
$Parameters = @{'tagName'=$TagName; 'tagValue'=$TagValue}
$chars = [char[]]"abcdef0123456789abcdef0123456789"
$AssignmentName = [string](($chars|Get-Random -Count 24) -join "")
New-AzPolicyAssignment -Name $AssignmentName -PolicyDefinition $Policy -Scope $Scope.Id -PolicyParameterObject $Parameters -DisplayName "$PolicyName - $TagName"


# Policies with just one parameter and managed identity

$PolicyName = "Inherit a tag from the resource group if missing"
$Policy = Get-AzPolicyDefinition -BuiltIn | Where-Object {$_.Properties.DisplayName -eq $PolicyName}
$Scope = Get-AzManagementGroup | where DisplayName -eq "hertes.net"

$TagName = "Owner"
$Parameters = @{'tagName'=$TagName}
$chars = [char[]]"abcdef0123456789abcdef0123456789"
$AssignmentName = [string](($chars|Get-Random -Count 24) -join "")
New-AzPolicyAssignment -Name $AssignmentName -PolicyDefinition $Policy -Scope $Scope.Id -PolicyParameterObject $Parameters -DisplayName "$PolicyName - $TagName" -IdentityType 'SystemAssigned' -Location "westeurope"