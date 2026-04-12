#Find stopped services:
Get-Service | Where-Object { $_.Status -eq "Stopped" }

#Find large files:
Get-ChildItem -File | Where-Object { $_.Length -gt 1MB }

#Find specific users:
Get-ADUser -Filter 'Enabled -eq $false' | 
    ForEach-Object { Enable-ADAccount -Identity $_ -WhatIf }


