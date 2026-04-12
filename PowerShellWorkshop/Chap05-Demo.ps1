"C:\Windows" | Get-ChildItem
#String is used for –Path, as this is a String-type positional parameter with pos. 0

Start-Process "C:\Windows\System32\notepad.exe"

Get-Process -Name "notepad" | Stop-Process
# Get-Process gives System.Diagnostics.Process object, which are taken for –InputObjekt in Stop-Process

Get-Process "sshd" | Get-Service 

Start-Process "C:\Windows\System32\notepad.exe"
Get-Process "notepad" | Stop-Service
# Error

