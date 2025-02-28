[CmdletBinding()]
param (

    [Parameter()]
    [Nullable[bool]]
    $MgmtIsCompute,

    [Parameter()]
    [String]
    $MgmtIp, 

    [Parameter()]
    [String]
    $MgmtSubnet,

    [Parameter()]
    [String]
    $MgmtGateway,

    [Parameter()]
    [String]
    $MgmtDns1,

    [Parameter()]
    [String]
    $MgmtDns2,

    [Parameter()]
    [int]
    $MgmtVlan, 
    
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

$MgmtNic = $null
Write-Host "Disconnect all but one network adapter. Keep the one connected, that you want to use for MANAGEMENT intent. Hit [ENTER] when done."
Read-Host
While($MgmtNic -eq $null)
{
    $MgmtNic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    If($MgmtNic -eq $null)
    {
        Start-Sleep -Seconds 5
        $MgmtNic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    }
    If($MgmtNic -eq $null)
    {
        Write-Host "No new network adapter found. Please connect a network adapter and hit [ENTER] when done." -ForegroundColor Red
        Read-Host
    }
}

Write-Host "Found this Network Adapter for MANAGEMENT intent:" -ForegroundColor Green
$MgmtNic | Format-Table Name,InterfaceDescription,LinkSpeed -AutoSize

If($MgmtNic.DriverProvider -eq "Microsoft")
{
    Write-Host "The network adapter you selected for MANAGEMENT intent is still using a Microsoft driver. Please install the correct driver later..."
}

If($MgmtIsCompute -eq $null){
    $MgmtIsComputeString = Read-Host "Do you want to use the card for management intent also for compute intent? [Y/n]"
    $MgmtIsCompute = (($MgmtIsComputeString -eq "Y") -or ($MgmtIsComputeString -eq "y") -or ($MgmtIsComputeString -eq "") -or ($MgmtIsComputeString -eq "Yes") -or ($MgmtIsComputeString -eq "yes"))
}

If(!$MgmtIsCompute)
{
    $CmptNic = $null
    Write-Host "Now also connect the NIC you want to use for COMPUTE intent. Hit [ENTER] when done."
    Read-Host
    While($CmptNic -eq $null)
    {
        $CmptNic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $MgmtNic.MacAddress) }
        If($CmptNic -eq $null)
        {
            Start-Sleep -Seconds 5
            $CmptNic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $MgmtNic.MacAddress) }
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

$Strg1Nic = $null
Write-Host "Now connect the first network adapter you want to use for STORAGE intent. Hit [ENTER] when done."
Read-Host
While($Strg1Nic -eq $null)
{
    $Strg1Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $MgmtNic.MacAddress) -and ($_.MacAddress -ne $CmptNic.MacAddress) }
    If($Strg1Nic -eq $null)
    {
        Start-Sleep -Seconds 5
        $Strg1Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $MgmtNic.MacAddress) -and ($_.MacAddress -ne $CmptNic.MacAddress) }
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
        $Strg2Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $MgmtNic.MacAddress) -and ($_.MacAddress -ne $CmptNic.MacAddress) -and ($_.MacAddress -ne $Strg1Nic.MacAddress) }
        If($Strg2Nic -eq $null)
        {
            Start-Sleep -Seconds 5
            $Strg2Nic = Get-NetAdapter | Where-Object { ($_.Status -eq "Up") -and ($_.MacAddress -ne $MgmtNic.MacAddress) -and ($_.MacAddress -ne $CmptNic.MacAddress) -and ($_.MacAddress -ne $Strg1Nic.MacAddress) }
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
If([string]::IsNullOrEmpty($MgmtIp)){      $MgmtIp     = Read-Host "IPv4 Address    Format 192.168.100.200 :" }
If([string]::IsNullOrEmpty($MgmtSubnet)){  $MgmtSubnet = Read-Host "Subnet Mask     Format 255.255.255.0   :" }
If([string]::IsNullOrEmpty($MgmtGateway)){ $MgmtGateway= Read-Host "Default Gateway Format 192.168.100.1   :" }
If([string]::IsNullOrEmpty($MgmtDns1)){    $MgmtDns1   = Read-Host "DNS Server 1    Format 192.168.100.2   :" }
If([string]::IsNullOrEmpty($MgmtDns2)){    $MgmtDns2   = Read-Host "DNS Server 2    Format 192.168.100.3   :" }
If([string]::IsNullOrEmpty($MgmtVlan)){    $MgmtVlan   = Read-Host "VLAN ID         Format 100             :" }

If(!$MgmtIsCompute)
{
    Write-Host "Enter the following networking information for the network adapter you want to use for COMPUTE intent."
    If([string]::IsNullOrEmpty($CmptIp)){      $CmptIp     = Read-Host "IPv4 Address    Format 192.168.100.200 :" }
    If([string]::IsNullOrEmpty($CmptSubnet)){  $CmptSubnet = Read-Host "Subnet Mask     Format 255.255.255.0   :" }
    If([string]::IsNullOrEmpty($CmptGateway)){ $CmptGateway= Read-Host "Default Gateway Format 192.168.100.1   :" }
    If([string]::IsNullOrEmpty($CmptDns1)){    $CmptDns1   = Read-Host "DNS Server 1    Format 192.168.100.2   :" }
    If([string]::IsNullOrEmpty($CmptDns2)){    $CmptDns2   = Read-Host "DNS Server 2    Format 192.168.100.3   :" }

}

Write-Host "Setting network adapter adresses for management intent now..."
#$MgmtNic | New-NetIPAddress -IPAddress $MgmtIp -PrefixLength (Convert-SubnetMaskToPrefix -SubnetMask $MgmtSubnet) -DefaultGateway $MgmtGateway

# Retrieve the current IP configuration of the network interface
$ipConfig = Get-NetIPConfiguration -InterfaceIndex $MgmtNic.ifIndex

# Check if a default gateway is already assigned
if ($ipConfig.IPv4DefaultGateway -eq $null) {
    # No default gateway assigned, proceed to set the new IP address and default gateway
    $MgmtNic | New-NetIPAddress -IPAddress $MgmtIp -PrefixLength (Convert-SubnetMaskToPrefix -SubnetMask $MgmtSubnet) -DefaultGateway $MgmtGateway
} else {
    # Default gateway already exists, handle accordingly
    Write-Host "Default gateway already exists for interface MANAGEMENT NIC... Only setting IP adress"
    $MgmtNic | Set-NetIPAddress -IPAddress $MgmtIp -PrefixLength (Convert-SubnetMaskToPrefix -SubnetMask $MgmtSubnet)
}


$MgmtNic | Set-DnsClientServerAddress -ServerAddresses $MgmtDns1,$MgmtDns2
Write-Host "Renaming network adapter to 'Management-01-NIC'..."
$MgmtNic = $MgmtNic | Rename-NetAdapter -NewName "Management-01-NIC" -PassThru
Write-Host "Setting network adapter adresses for management intent done."
Write-Host "Setting VLAN for management intent now..."
$MgmtNic | Set-NetAdapter -VlanID $MgmtVlan
Write-Host "Setting VLAN for management intent done."

Write-Host "Setting time server to $NtpServer..."
w32tm.exe /config /manualpeerlist:$NtpServer /syncfromflags:manual /reliable:yes /update
Write-Host "Restarting time service..."
Restart-Service w32time
Write-Host "Setting time server done."

If(!$MgmtIsCompute)
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