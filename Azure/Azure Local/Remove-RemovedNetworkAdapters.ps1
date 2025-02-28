# This script will remove all network adapters, that the system has previously seen but are not existing anymore.

# Enumerate all devices, including hidden ones
$nonPresentAdapter = (pnputil.exe /enum-devices /class net /disconnected)

# Filter out non-present network adapter IDs
# $nonPresentAdapterIDs = ($nonPresentAdapter | Select-String "Instance ID:*") -split(" ") | where-object {$_ -notin ("","Instance","ID:")}
$nonPresentAdapterIDs = ($nonPresentAdapter | Select-String "Instance ID:*")  -replace "Instance ID\s*:\s*", ""

Write-Host "These are the non-presen adapters:"
$nonPresentAdapter
Read-Host "Proceed? [CTRL+C] to cancel"

foreach ($id in $nonPresentAdapterIDs) {
    pnputil.exe /remove-device "$id"    
}

"If there are still non-present adapters, you can try to remove them manually by running the following command:"
"pnputil.exe /remove-device <ID>"
"Here are the non-present adapters (if any):"
Get-PnpDevice -Class Net | Where-Object Status -eq 'Unknown'