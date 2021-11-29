<#
    .DESCRIPTION
        This script updates the DNS Zones and Records on an Windows Server DNS-Server when public IPs are changed, i.e. through changing providers.
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
        LASTEDIT: 2021/11/29
#>

[CmdletBinding()]
param (
    # Should we update the TTLs of the records?
    $UpdateTTLs = $true, 

    # New TTL in Minutes
    $NewTTLInMinutes = 1,

    # Should we update the A records with the new IPs?
    $UpdateRecords = $false,

    # If this is set to $false, all DNS Zones will be processed
    $JustUSeTheNamedListOfZones = $true,

    # This is just used when $JustUSeTheNamedListOfZones is set to $true
    [string[]]$DNSZones = "hertes.net" 

)

# This is the Mapping Table for old and new IPs
$IpAdressMappingTable = @()

$IpAdressMappingTable += [PSCustomObject]@{
    Name = "Zitzschennet1" # This is just a name - not used yet
    OldIpv4Adress = "94.136.173.66"
    NewIpv4Adress = "85.190.178.xxx"
}

$IpAdressMappingTable += [PSCustomObject]@{
    Name = "hertes.net" # This is just a name - not used yet
    OldIpv4Adress = "94.136.173.67"
    NewIpv4Adress = "85.190.178.135"
}

$IpAdressMappingTable += [PSCustomObject]@{
    Name = "webseite4dich.de" # This is just a name - not used yet
    OldIpv4Adress = "185.19.52.224"
    NewIpv4Adress = "85.190.178.136"
}

$IpAdressMappingTable += [PSCustomObject]@{
    Name = "Zitzschennet2" # This is just a name - not used yet
    OldIpv4Adress = "185.19.53.224"
    NewIpv4Adress = "85.190.178.xxx"
}


Try {
    Import-Module "DnsServer" -ErrorAction Stop
}
Catch {
    Write-Host "Error - DNS-Server Module not found!"
}

If($JustUSeTheNamedListOfZones -eq $false)
{
    $DNSZones = (Get-DnsServerZone).ZoneName
}

If($UpdateTTLs)
{
    $TTL = [System.TimeSpan]::FromMinutes($NewTTLInMinutes)
    ForEach($DNSZone in $DNSZones)
    {
        $SOA = Get-DNSServerResourceRecord -RRType SOA -ZoneName $DNSZone
        If($SOA.RecordData.MinimumTimeToLive -ne $TTL) { 
            $NewSOA = $SOA.Clone() 
            $NewSOA.RecordData.MinimumTimeToLive = $TTL
            Set-DnsServerResourceRecord -NewInputObject $NewSOA -OldInputObject $SOA -ZoneName $DNSZone 
        }

        Get-DnsServerResourceRecord -ZoneName $DNSZone -RRType A | ForEach-Object {
                                                                        $OldObject = $null
                                                                        $OldObject = $_
                                                                        $NewObject = $OldObject.Clone()
                                                                        $NewObject.TimeToLive = $TTL
                                                                        Set-DnsServerResourceRecord -ZoneName $DNSZone -OldInputObject $OldObject -NewInputObject $NewObject
                                                                    }
    }
}

If($UpdateRecords)
{
    ForEach($DNSZone in $DNSZones) # Running through all DNS Zones
    {
        ForEach($IpAdressMapping in $IpAdressMappingTable) # Running through all IP Adress Mappings
        {
            Get-DnsServerResourceRecord -ZoneName $DNSZone -RRType A | Where-Object {$_.RecordData.IPv4Address -eq ($IpAdressMapping.OldIpv4Adress)} | ForEach-Object {
                                                                        $OldObject = $null
                                                                        $OldObject = $_
                                                                        $NewObject = $OldObject.Clone()
                                                                        $NewObject.RecordData.IPv4Address = ($IpAdressMapping.NewIpv4Adress)
                                                                        Set-DnsServerResourceRecord -ZoneName $DNSZone -OldInputObject $OldObject -NewInputObject $NewObject
                                                                    }
        }
    }
}
