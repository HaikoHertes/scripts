Invoke-Command -ComputerName Lab02 -ScriptBlock {
    hostname
    Get-Service | Select-Object -First 5
}
# Single command, executed remotely, output comes back as object(s)



$cred = Get-Credential


Invoke-Command -ComputerName DC01.lab.local -Credential $cred -ScriptBlock {
    hostname
    Get-WindowsFeature | Where-Object {$_.Installed -eq $true} | Select-Object -First 5
} | Select Name,DisplayName


Invoke-Command -ComputerName DC01.lab.local -ScriptBlock {
    Get-ADUser -Filter * -ResultSetSize 5
}


Invoke-Command -ComputerName "Lab01.lab.local","Lab02.lab.local" -Credential $cred -ScriptBlock {
    [PSCustomObject]@{
        Computer = hostname
        RunningServices = (Get-Service | Where-Object Status -eq "Running").Count
    }
}