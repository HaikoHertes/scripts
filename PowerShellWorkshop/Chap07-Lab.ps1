$departments = @("IT","Finance")

$report = foreach ($dept in $departments) 
{
    Get-ADUser -Filter "Department -eq '$dept'" -Properties Department, Enabled |
        ForEach-Object {
            [PSCustomObject]@{
                Department = $dept
                Name       = $_.Name
                Enabled    = $_.Enabled
            }
        }
}

$report