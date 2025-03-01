[CmdletBinding()]
param (

    [Parameter()]
    [Nullable[bool]]
    $Mgmt1IsCompute,

    [Parameter()]
    [String]
    $Mgmt1Ip, 

    [Parameter()]
    [String]
    $Mgmt1Subnet,

    [Parameter()]
    [String]
    $Mgmt1Gateway,

    [Parameter()]
    [String]
    $Mgmt1Dns1,

    [Parameter()]
    [String]
    $Mgmt1Dns2,

    [Parameter()]
    [int]
    $Mgmt1Vlan, 
    
    [Parameter()]
    [String]
    $CmptIp, 

    [Parameter()]
    [String]
    $CmptSubnet,

    [Parameter()]
    [String]
    $CmptDns1,

    [Parameter()]
    [String]
    $CmptDns2
)

function Convert-SubnetMaskToPrefix {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SubnetMask
    )
    
    # Split the subnet mask into octets and convert to binary
    $binaryMask = ($SubnetMask -split '\.') | ForEach-Object {
        [Convert]::ToString([int]$_, 2).PadLeft(8, '0')
    }
    
    # Count the number of 1s in the binary representation
    return ($binaryMask -join '').ToCharArray() | Where-Object { $_ -eq '1' } | Measure-Object | Select-Object -ExpandProperty Count
}

$Mgmt1Nic = $null
Write-Host "Disconnect all but one network adapter. Keep the one connected, that you want to use for MANAGEMENT intent. Hit [ENTER] when done."
Read-Host
While($Mgmt1Nic -eq $null)
{
    $Mgmt1Nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    If($Mgmt1Nic -eq $null)
    {
        Start-Sleep -Seconds 5
        $Mgmt1Nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    }
    If($Mgmt1Nic -eq $null)
    {
        Write-Host "No new network adapter found. Please connect a network adapter and hit [ENTER] when done." -ForegroundColor Red
        Read-Host
    }
}

Write-Host "Found this Network Adapter for MANAGEMENT intent:" -ForegroundColor Green
$Mgmt1Nic | Format-Table Name,InterfaceDescription,LinkSpeed -AutoSize

If($Mgmt1Nic.DriverProvider -eq "Microsoft")
{
    Write-Host "The network adapter you selected for MANAGEMENT intent is still using a Microsoft driver. Please install the correct driver later..."
}

If($Mgmt1IsCompute -eq $null){
    $Mgmt1IsComputeString = Read-Host "Do you want to use the card for management intent also for compute intent? [Y/n]"
    $Mgmt1IsCompute = (($Mgmt1IsComputeString -eq "Y") -or ($Mgmt1IsComputeString -eq "y") -or ($Mgmt1IsComputeString -eq "") -or ($Mgmt1IsComputeString -eq "Yes") -or ($Mgmt1IsComputeString -eq "yes"))
}

If(!$Mgmt1IsCompute)
{
    $CmptNic = $null
    Write-Host "Now also connect the NIC you want to use for COMPUTE intent. Hit [ENTER] when done."
    Read-Host
    While($CmptNic -eq $null)
    {
        $CmptNic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) }
        If($CmptNic -eq $null)
        {
            Start-Sleep -Seconds 5
            $CmptNic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) }
        }
        If($CmptNic -eq $null)
        {
            Write-Host "No new network adapter found. Please connect a network adapter and hit [ENTER] when done." -ForegroundColor Red
            Read-Host
        }
    }

    Write-Host "Found this Network Adapter for COMPUTE intent:" -ForegroundColor Green
    $CmptNic | Format-Table Name,InterfaceDescription,LinkSpeed -AutoSize


    If($CmptNic.DriverProvider -eq "Microsoft")
    {
        Write-Host "The network adapter you selected for COMPUTE intent is still using a Microsoft driver. Please install the correct driver later..."
    }
}

If($2ndMgmtNIC -eq $null){
    $2ndMgmtNICString = Read-Host "Do you want to use a 2nd NIC for management intent? [Y/n]"
    $2ndMgmtNIC = (($2ndMgmtNICString -eq "Y") -or ($2ndMgmtNICString -eq "y") -or ($2ndMgmtNICString -eq "") -or ($2ndMgmtNICString -eq "Yes") -or ($2ndMgmtNICString -eq "yes"))
}

If($2ndMgmtNIC)
{
    $Mgmt2Nic = $null
    Write-Host "Now also connect the 2nd NIC you want to use for MANAGEMENT intent. Hit [ENTER] when done."
    Read-Host
    While($Mgmt2Nic -eq $null)
    {
        $Mgmt2Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) -and ($_.MacAddress -ne $CmptNic.MacAddress)}
        If($Mgmt2Nic -eq $null)
        {
            Start-Sleep -Seconds 5
            $Mgmt2Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) -and ($_.MacAddress -ne $CmptNic.MacAddress) }
        }
        If($Mgmt2Nic -eq $null)
        {
            Write-Host "No new network adapter found. Please connect a network adapter and hit [ENTER] when done." -ForegroundColor Red
            Read-Host
        }
    }

    Write-Host "Found this Network Adapter for MANAGEMENT intent (2nd NIC):" -ForegroundColor Green
    $Mgmt2Nic | Format-Table Name,InterfaceDescription,LinkSpeed -AutoSize


    If($Mgmt2Nic.DriverProvider -eq "Microsoft")
    {
        Write-Host "The network adapter you selected for MANAGEMENT intent (2nd NIC) is still using a Microsoft driver. Please install the correct driver later..."
    }
}



$Strg1Nic = $null
Write-Host "Now connect the first network adapter you want to use for STORAGE intent. Hit [ENTER] when done."
Read-Host
While($Strg1Nic -eq $null)
{
    $Strg1Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) -and ($_.MacAddress -ne $Mgmt2Nic.MacAddress) -and ($_.MacAddress -ne $CmptNic.MacAddress) }
    If($Strg1Nic -eq $null)
    {
        Start-Sleep -Seconds 5
        $Strg1Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) -and ($_.MacAddress -ne $Mgmt2Nic.MacAddress)  -and ($_.MacAddress -ne $CmptNic.MacAddress) }
    }
    If($Strg1Nic -eq $null)
    {
        Write-Host "No new network adapter found. Please connect a network adapter and hit [ENTER] when done." -ForegroundColor Red
        Read-Host
    }
}

Write-Host "Found this Network Adapter for STORAGE intent (1st NIC):" -ForegroundColor Green
$Strg1Nic | Format-Table Name,InterfaceDescription,LinkSpeed -AutoSize

If($Strg1Nic.DriverProvider -eq "Microsoft")
{
    Write-Host "The network adapter you selected for STORAGE intent is still using a Microsoft driver. Please install the correct driver later..."
}

$TwoStorageNicsString = Read-Host "Do you want to use a second NIC for storage intent? [Y/n]"
$TwoStorageNics = (($TwoStorageNicsString -eq "Y") -or ($TwoStorageNicsString -eq "y") -or ($TwoStorageNicsString -eq "") -or ($TwoStorageNicsString -eq "Yes") -or ($TwoStorageNicsString -eq "yes"))
If($TwoStorageNics)
{
    $Strg2Nic = $null
    Write-Host "Now connect the second network adapter you want to use for STORAGE intent. Hit [ENTER] when done."
    Read-Host
    While($Strg2Nic -eq $null)
    {
        $Strg2Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) -and ($_.MacAddress -ne $Mgmt2Nic.MacAddress)  -and ($_.MacAddress -ne $CmptNic.MacAddress) -and ($_.MacAddress -ne $Strg1Nic.MacAddress) }
        If($Strg2Nic -eq $null)
        {
            Start-Sleep -Seconds 5
            $Strg2Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $Mgmt1Nic.MacAddress) -and ($_.MacAddress -ne $Mgmt2Nic.MacAddress)  -and ($_.MacAddress -ne $CmptNic.MacAddress) -and ($_.MacAddress -ne $Strg1Nic.MacAddress) }
        }
        If($Strg2Nic -eq $null)
        {
            Write-Host "No new network adapter found. Please connect a network adapter and hit [ENTER] when done." -ForegroundColor Red
            Read-Host
        }
    }

    Write-Host "Found this Network Adapter for STORAGE intent (2nd NIC):" -ForegroundColor Green
    $Strg2Nic | Format-Table Name,InterfaceDescription,LinkSpeed -AutoSize

    
    If($Strg2Nic.DriverProvider -eq "Microsoft")
    {
        Write-Host "The network adapter you selected for STORAGE intent (2nd Adapter) is still using a Microsoft driver. Please install the correct driver later..."
    }
}

$CustomNtpServerString = Read-Host "Do you want to use a custom NTP server? Otherwise pool.ntp.org will be used. [y/N]"
$CustomNtpServer = (($CustomNtpServerString -eq "Y") -or ($CustomNtpServerString -eq "y") -or ($CustomNtpServerString -eq "Yes") -or ($CustomNtpServerString -eq "yes"))
If($CustomNtpServer)
{
    $NtpServer = Read-Host "Enter the IP address or hostname of the NTP server you want to use. Format: host.domain.com"
}
else {
    $NtpServer = "pool.ntp.org"
}

# $ManagementIsCompute
# $AllNetAdapters = Get-NetAdapter
Write-Host "Enter the following networking information for the network adapter you want to use for MANAGEMENT intent."
If([string]::IsNullOrEmpty($Mgmt1Ip)){      $Mgmt1Ip     = Read-Host "IPv4 Address    Format 192.168.100.200 :" }
If([string]::IsNullOrEmpty($Mgmt1Subnet)){  $Mgmt1Subnet = Read-Host "Subnet Mask     Format 255.255.255.0   :" }
If([string]::IsNullOrEmpty($Mgmt1Gateway)){ $Mgmt1Gateway= Read-Host "Default Gateway Format 192.168.100.1   :" }
If([string]::IsNullOrEmpty($Mgmt1Dns1)){    $Mgmt1Dns1   = Read-Host "DNS Server 1    Format 192.168.100.2   :" }
If([string]::IsNullOrEmpty($Mgmt1Dns2)){    $Mgmt1Dns2   = Read-Host "DNS Server 2    Format 192.168.100.3   :" }
If([string]::IsNullOrEmpty($Mgmt1Vlan)){    $Mgmt1Vlan   = Read-Host "VLAN ID         Format 100             :" }

If(!$Mgmt1IsCompute)
{
    Write-Host "Enter the following networking information for the network adapter you want to use for COMPUTE intent."
    If([string]::IsNullOrEmpty($CmptIp)){      $CmptIp     = Read-Host "IPv4 Address    Format 192.168.100.200 :" }
    If([string]::IsNullOrEmpty($CmptSubnet)){  $CmptSubnet = Read-Host "Subnet Mask     Format 255.255.255.0   :" }
    If([string]::IsNullOrEmpty($CmptGateway)){ $CmptGateway= Read-Host "Default Gateway Format 192.168.100.1   :" }
    If([string]::IsNullOrEmpty($CmptDns1)){    $CmptDns1   = Read-Host "DNS Server 1    Format 192.168.100.2   :" }
    If([string]::IsNullOrEmpty($CmptDns2)){    $CmptDns2   = Read-Host "DNS Server 2    Format 192.168.100.3   :" }

}

Write-Host "Setting network adapter adresses for management intent now..."
#$Mgmt1Nic | New-NetIPAddress -IPAddress $Mgmt1Ip -PrefixLength (Convert-SubnetMaskToPrefix -SubnetMask $Mgmt1Subnet) -DefaultGateway $Mgmt1Gateway

# Retrieve the current IP configuration of the network interface
$ipConfig = Get-NetIPConfiguration -InterfaceIndex $Mgmt1Nic.ifIndex

# Check if a default gateway is already assigned
if ($ipConfig.IPv4DefaultGateway -eq $null) {
    # No default gateway assigned, proceed to set the new IP address and default gateway
    $Mgmt1Nic | New-NetIPAddress -IPAddress $Mgmt1Ip -PrefixLength (Convert-SubnetMaskToPrefix -SubnetMask $Mgmt1Subnet) -DefaultGateway $Mgmt1Gateway
} else {
    # Default gateway already exists, handle accordingly
    Write-Host "Default gateway already exists for interface MANAGEMENT NIC... Only setting IP adress"
    $Mgmt1Nic | Set-NetIPAddress -IPAddress $Mgmt1Ip -PrefixLength (Convert-SubnetMaskToPrefix -SubnetMask $Mgmt1Subnet)
}


$Mgmt1Nic | Set-DnsClientServerAddress -ServerAddresses $Mgmt1Dns1,$Mgmt1Dns2
Write-Host "Renaming network adapter to 'Management-01-NIC'..."
$Mgmt1Nic = $Mgmt1Nic | Rename-NetAdapter -NewName "Management-01-NIC" -PassThru
Write-Host "Setting network adapter adresses for management intent done."
Write-Host "Setting VLAN for management intent now..."
$Mgmt1Nic | Set-NetAdapter -VlanID $Mgmt1Vlan
Write-Host "Setting VLAN for management intent done."

Write-Host "Setting time server to $NtpServer..."
w32tm.exe /config /manualpeerlist:$NtpServer /syncfromflags:manual /reliable:yes /update
Write-Host "Restarting time service..."
Restart-Service w32time
Write-Host "Setting time server done."

If($2ndMgmtNIC)
{
    Write-Host "Renaming network adapter for 2nd management intent to 'Management-02-NIC'..."
    $Mgmt2Nic = $Mgmt2Nic | Rename-NetAdapter -NewName "Management-02-NIC" -PassThru
    Write-Host "Renaming network adapter for 2nd management intent done."
}

If(!$Mgmt1IsCompute)
{
    Write-Host "Setting network adapter adresses for compute intent now..."
    $CmptNic | New-NetIPAddress -IPAddress $CmptIp -PrefixLength (Convert-SubnetMaskToPrefix -SubnetMask $CmptSubnet)
    $CmptNic | Set-DnsClientServerAddress -ServerAddresses $CmptDns1,$CmptDns2
    Write-Host "Renaming network adapter to 'Compute-01-NIC'..."
    $CmptNic = $CmptNic | Rename-NetAdapter -NewName "Compute-01-NIC" -PassThru
    Write-Host "Setting network adapter adresses for compute intent done."
}
Write-Host "Renaming network adapter to 'Storage-01-NIC'..."
$Strg1Nic = $Strg1Nic | Rename-NetAdapter -NewName "Storage-01-NIC" -PassThru
Write-Host "Setting network adapter name for storage intent done."

If($TwoStorageNics)
{
    Write-Host "Renaming network adapter to 'Storage-02-NIC'..."
    $Strg2Nic = $Strg2Nic | Rename-NetAdapter -NewName "Storage-02-NIC" -PassThru
    Write-Host "Setting network adapter name for storage intent done."    
}

Write-Host "Network adapter configuration done. This is the current configuration:"
Get-NetAdapter |
    Where-Object { $_.Status -eq "Up" } |
    ForEach-Object {
        $adapter = $_
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 |
                    Select-Object -ExpandProperty IPAddress
        [PSCustomObject]@{
            Name                 = $adapter.Name
            InterfaceDescription = $adapter.InterfaceDescription
            Status               = $adapter.Status
            MediaConnectionState = $adapter.MediaConnectionState
            LinkSpeed            = $adapter.LinkSpeed
            VlanID               = $adapter.VlanID
            IPAddress            = $ipConfig -join ', '
        }
    } |
    Format-Table -AutoSize