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
    Name = "IP1" # This is just a name - not used yet
    OldIpv4Adress = "11.22.33.44"
    NewIpv4Adress = "55.66.77.88"
}

$IpAdressMappingTable += [PSCustomObject]@{
    Name = "IP2" # This is just a name - not used yet
    OldIpv4Adress = "10.10.10.10"
    NewIpv4Adress = "20.20.20.20"
}

$IpAdressMappingTable += [PSCustomObject]@{
    Name = "IP3" # This is just a name - not used yet
    OldIpv4Adress = "47.11.08.15"
    NewIpv4Adress = "42.19.13.11"
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
            Write-Host "Updating $DNSZone SOA Record with new TTL $NewTTLInMinutes minutes..."
            Set-DnsServerResourceRecord -NewInputObject $NewSOA -OldInputObject $SOA -ZoneName $DNSZone 
        }

        Get-DnsServerResourceRecord -ZoneName $DNSZone -RRType A | ForEach-Object {
                                                                        $OldObject = $null
                                                                        $OldObject = $_
                                                                        $NewObject = $OldObject.Clone()
                                                                        $NewObject.TimeToLive = $TTL
                                                                        Write-Host "Updating $DNSZone A Record with new TTL $NewTTLInMinutes minutes - Hostname: $($NewObject.HostName)"
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
                                                                        Write-Host "Updating $DNSZone A Record with new IP $($IpAdressMapping.NewIpv4Adress) - Hostname: $($NewObject.HostName)"
                                                                        Set-DnsServerResourceRecord -ZoneName $DNSZone -OldInputObject $OldObject -NewInputObject $NewObject
                                                                    }
        }
    }
}
