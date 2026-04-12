Get-Process
# Too much information!

Get-Process | Sort-Object CPU -Descending
# Same data, different order

Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
# Top 5 CPU consumers

Get-Process | Sort-Object CPU -Descending |
Select-Object -First 5 Name, CPU
# Reduced information

Get-Process | Sort-Object CPU -Descending |
Select-Object -First 5 Name, CPU | Get-Member
# Majority of properties is gone now!

