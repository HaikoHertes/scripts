@echo off
setlocal

:: Define parameters
set MgmtIp=192.168.32.12
set MgmtSubnet=255.255.255.0
set MgmtGateway=192.168.32.1
set MgmtDns1=192.168.40.1
set MgmtDns2=192.168.32.1
set MgmtVlan=0

:: Execute PowerShell script with parameters
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "Set-NetworkingPrerequisites.ps1" ^
  -MgmtIp %MgmtIp% ^
  -MgmtSubnet %MgmtSubnet% ^
  -MgmtGateway %MgmtGateway% ^
  -MgmtDns1 %MgmtDns1% ^
  -MgmtDns2 %MgmtDns2% ^
  -MgmtVlan %MgmtVlan%
  
endlocal