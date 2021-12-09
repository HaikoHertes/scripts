Install-Module -Name Az -AllowClobber -Scope CurrentUser
Login-AzAccount
$SubID = (Get-AzSubscription -SubscriptionName "Microsoft Azure Sponsorship").Id            # Put your Subscription Name here
Select-AzSubscription $SubId
$result = Get-AzResourceGroup | `                                                                     # Get all RGs in Subscription
    ForEach-Object {Get-AzRoleAssignment -ResourceGroupName $_.ResourceGroupName} | `       # Get all Role Assignments in all RGs
    Where-Object {$_.Scope -like "/subscriptions/$SubId/resourceGroups/*/providers/*"}      # Get assignments directly on resources
Clear-Host
Write-Output "These are the assigned roles on single resources:"
$result | Format-Table SignInName,RoleDefinitionName,Scope                                  # Format output as nice table
