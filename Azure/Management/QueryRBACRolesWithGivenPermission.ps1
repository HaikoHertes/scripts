# Define Permission here - allows Wildcard *
$Operation = "Microsoft.Insights/LogDefinitions/Read"

$FoundRoles = @()
ForEach($Role in (Get-AzRoleDefinition))
{
    $PermissionFound = $false
    ForEach($Action in ([string[]]($Role.Actions)))
    {
        If(($Action -like $Operation) -or ($Operation -like $Action)) # Wildcard only supported on right side!
        {
            $FoundRoles += $Role
            $PermissionFound = $true
            Break # End iteration of Actions
        }
    }
    If($PermissionFound)
    {
        Continue # Next Role
    }
    ForEach($DataAction in ([string[]]($Role.DataActions)))
    {
        If(($DataAction -like $Operation) -or ($Operation -like $DataAction)) # Wildcard only supported on right side!
        {
            $FoundRoles += $Role
            $PermissionFound = $true
            Break # End iteration of Actions
        }
    }

}

$FoundRoles | Sort-Object Name | Format-Table Name,Id,IsCustom,Description