Get-Service NonExistingService
Write-Host "Script continues"


Get-Service NonExistingService -ErrorAction Stop
# Terminates here!


try {
    Get-Service NonExistingService -ErrorAction Stop
}
catch {
    "Handled the error safely."
}


Stop-Service W32Time -WhatIf


Stop-Service W32Time -Confirm
