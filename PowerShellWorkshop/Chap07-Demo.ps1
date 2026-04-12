$servers = @("Lab01","Lab02")


foreach ($server in $servers) {
    "==== $server ===="
}


foreach ($server in $servers) {
    "==== $server ===="
    Invoke-Command -ComputerName $server -ScriptBlock {
        Get-Service
    }
}


foreach ($server in $servers) {
    "==== $server ===="
    Invoke-Command -ComputerName $server -ScriptBlock {
        Get-Service | Where-Object { $_.Status -eq "Running" }
    }
}
