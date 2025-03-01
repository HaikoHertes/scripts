@echo off
setlocal

:: Define parameters
set Mgmt1Ip=192.168.32.12
set Mgmt1Subnet=255.255.255.0
set Mgmt1Gateway=192.168.32.1
set Mgmt1Dns1=192.168.40.1
set Mgmt1Dns2=192.168.32.1
set Mgmt1Vlan=0

:: Execute PowerShell script with parameters
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -File "Set-NetworkingPrerequisites.ps1" ^
  -Mgmt1Ip %Mgmt1Ip% ^
  -Mgmt1Subnet %Mgmt1Subnet% ^
  -Mgmt1Gateway %Mgmt1Gateway% ^
  -Mgmt1Dns1 %Mgmt1Dns1% ^
  -Mgmt1Dns2 %Mgmt1Dns2% ^
  -Mgmt1Vlan %Mgmt1Vlan%
  
endlocal