<#
.SYNOPSIS
    Exports or imports Windows VPN connections to/from a JSON file.

.DESCRIPTION
    Clones Windows VPN connection profiles between devices via a JSON export file.
    Run with -Mode Export on the source device, copy the file, then run with
    -Mode Import on the target device.

    Supported tunnel types : IKEv2, SSTP, L2TP, PPTP, Automatic
    Captured settings       : server address, tunnel type, authentication,
                              encryption, IPsec policy (IKEv2), EAP XML config,
                              routes, DNS suffix, idle disconnect timeout,
                              split tunneling, credential flags

.PARAMETER Mode
    Export  – saves all VPN connections to a JSON file.
    Import  – recreates VPN connections from a JSON file.

.PARAMETER FilePath
    Path to the JSON file. Defaults to "VpnConnections.json" in the current
    directory.

.PARAMETER AllUserConnection
    Export : also include machine-level (all-user) VPN connections.
    Import : create connections as machine-level (requires elevation).

.EXAMPLE
    # Export all per-user VPN connections
    .\CloneVPNSettings.ps1 -Mode Export -FilePath C:\Temp\vpn.json

.EXAMPLE
    # Export per-user AND machine-level VPN connections
    .\CloneVPNSettings.ps1 -Mode Export -FilePath C:\Temp\vpn.json -AllUserConnection

.EXAMPLE
    # Import VPN connections (run as the target user; elevate for AllUser entries)
    .\CloneVPNSettings.ps1 -Mode Import -FilePath C:\Temp\vpn.json
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Export', 'Import')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$FilePath = '.\VpnConnections.json',

    [Parameter(Mandatory = $false)]
    [switch]$AllUserConnection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Helpers ─────────────────────────────────────────────────────────────

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-IPsecConfig {
    param([string]$ConnectionName)
    try {
        $cfg = Get-VpnConnectionIPsecConfiguration -ConnectionName $ConnectionName -ErrorAction Stop
        return [ordered]@{
            AuthenticationTransformConstants = [string]$cfg.AuthenticationTransformConstants
            CipherTransformConstants         = [string]$cfg.CipherTransformConstants
            EncryptionMethod                 = [string]$cfg.EncryptionMethod
            IntegrityCheckMethod             = [string]$cfg.IntegrityCheckMethod
            DHGroup                          = [string]$cfg.DHGroup
            PfsGroup                         = [string]$cfg.PfsGroup
        }
    }
    catch { return $null }
}

function Get-EapXml {
    param([object]$Connection)
    try {
        if ($null -eq $Connection.EapConfigXmlStream) { return $null }
        $Connection.EapConfigXmlStream.Position = 0
        $reader = [System.IO.StreamReader]::new($Connection.EapConfigXmlStream)
        $xml = $reader.ReadToEnd()
        $reader.Close()
        return $xml
    }
    catch { return $null }
}

#endregion

#region ── Export ──────────────────────────────────────────────────────────────

function Export-VpnConnections {
    param(
        [string]$FilePath,
        [bool]$IncludeAllUser
    )

    Write-Host 'Collecting VPN connections...' -ForegroundColor Cyan

    # Gather connections, tagging each with its scope
    $tagged = [System.Collections.Generic.List[hashtable]]::new()

    $userConns = Get-VpnConnection -ErrorAction SilentlyContinue
    foreach ($c in $userConns) { $tagged.Add(@{ Conn = $c; IsAllUser = $false }) }

    if ($IncludeAllUser) {
        $allUserConns = Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue
        foreach ($c in $allUserConns) { $tagged.Add(@{ Conn = $c; IsAllUser = $true }) }
    }

    if ($tagged.Count -eq 0) {
        Write-Warning 'No VPN connections found.'
        return
    }

    $exportList = [System.Collections.Generic.List[object]]::new()

    foreach ($item in $tagged) {
        $conn = $item.Conn
        Write-Host "  Exporting: $($conn.Name)" -ForegroundColor Yellow

        $entry = [ordered]@{
            Name                  = $conn.Name
            ServerAddress         = $conn.ServerAddress
            TunnelType            = [string]$conn.TunnelType
            AuthenticationMethod  = ($conn.AuthenticationMethod | ForEach-Object { [string]$_ }) -join ','
            EncryptionLevel       = [string]$conn.EncryptionLevel
            SplitTunneling        = [bool]$conn.SplitTunneling
            RememberCredential    = [bool]$conn.RememberCredential
            UseWinlogonCredential = [bool]$conn.UseWinlogonCredential
            DnsSuffix             = $conn.DnsSuffix
            IdleDisconnectSeconds = [int]$conn.IdleDisconnectSeconds
            AllUserConnection     = $item.IsAllUser
            Routes                = @()
            IPsecConfiguration    = $null
            EapConfigXml          = $null
        }

        if ($conn.Routes -and $conn.Routes.Count -gt 0) {
            $entry.Routes = @(
                $conn.Routes | ForEach-Object {
                    [ordered]@{
                        DestinationPrefix = $_.DestinationPrefix
                        RouteMetric       = [int]$_.RouteMetric
                    }
                }
            )
        }

        if ($conn.TunnelType -eq 'IKEv2') {
            $entry.IPsecConfiguration = Get-IPsecConfig -ConnectionName $conn.Name
        }

        $entry.EapConfigXml = Get-EapXml -Connection $conn

        $exportList.Add($entry)
    }

    $exportList | ConvertTo-Json -Depth 10 | Set-Content -Path $FilePath -Encoding UTF8
    Write-Host "`nExported $($exportList.Count) connection(s) to: $FilePath" -ForegroundColor Green
}

#endregion

#region ── Import ──────────────────────────────────────────────────────────────

function Import-VpnConnections {
    param([string]$FilePath)

    if (-not (Test-Path -Path $FilePath)) {
        throw "Import file not found: $FilePath"
    }

    Write-Host "Loading VPN connections from $FilePath..." -ForegroundColor Cyan
    $importList = Get-Content -Path $FilePath -Encoding UTF8 -Raw | ConvertFrom-Json

    # Warn early if we need elevation for any AllUser connection
    $needsAdmin = @($importList | Where-Object { $_.AllUserConnection }).Count -gt 0
    if ($needsAdmin -and -not (Test-IsAdmin)) {
        Write-Warning 'One or more connections are machine-level (AllUserConnection = true). Elevation is required to import them. Other connections will still be imported.'
    }

    foreach ($conn in $importList) {
        $name = $conn.Name

        # Skip AllUser entries when not elevated
        if ($conn.AllUserConnection -and -not (Test-IsAdmin)) {
            Write-Warning "  Skipping '$name' (AllUserConnection – requires admin)."
            continue
        }

        # Remove existing connection of the same name
        $removeParams = @{ Name = $name; Force = $true; ErrorAction = 'SilentlyContinue' }
        if ($conn.AllUserConnection) { $removeParams.AllUserConnection = $true }
        Remove-VpnConnection @removeParams

        Write-Host "  Importing: $name" -ForegroundColor Yellow

        # ── Build Add-VpnConnection parameters ────────────────────────────────
        $authMethods = ($conn.AuthenticationMethod -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }

        $addParams = @{
            Name                  = $name
            ServerAddress         = $conn.ServerAddress
            TunnelType            = $conn.TunnelType
            EncryptionLevel       = $conn.EncryptionLevel
            SplitTunneling        = [bool]$conn.SplitTunneling
            RememberCredential    = [bool]$conn.RememberCredential
            UseWinlogonCredential = [bool]$conn.UseWinlogonCredential
            PassThru              = $true
            Force                 = $true
            ErrorAction           = 'Stop'
        }

        if ($authMethods.Count -eq 1) {
            $addParams.AuthenticationMethod = $authMethods[0]
        }
        elseif ($authMethods.Count -gt 1) {
            $addParams.AuthenticationMethod = $authMethods
        }

        if ($conn.DnsSuffix) { $addParams.DnsSuffix = $conn.DnsSuffix }
        if ($conn.IdleDisconnectSeconds -gt 0) { $addParams.IdleDisconnectSeconds = $conn.IdleDisconnectSeconds }
        if ($conn.AllUserConnection) { $addParams.AllUserConnection = $true }

        # Restore EAP XML configuration
        if ($conn.EapConfigXml) {
            try {
                $stream = [System.IO.MemoryStream]::new()
                $writer = [System.IO.StreamWriter]::new($stream)
                $writer.Write($conn.EapConfigXml)
                $writer.Flush()
                $stream.Position = 0
                $addParams.EapConfigXmlStream = $stream
            }
            catch {
                Write-Warning "  Could not restore EAP config for '$name': $_"
            }
        }

        try {
            $null = Add-VpnConnection @addParams

            # ── Restore IPsec configuration (IKEv2 only) ──────────────────
            if ($conn.TunnelType -eq 'IKEv2' -and $conn.IPsecConfiguration) {
                $ipsec = $conn.IPsecConfiguration
                $ipsecParams = @{
                    ConnectionName                   = $name
                    AuthenticationTransformConstants = $ipsec.AuthenticationTransformConstants
                    CipherTransformConstants         = $ipsec.CipherTransformConstants
                    EncryptionMethod                 = $ipsec.EncryptionMethod
                    IntegrityCheckMethod             = $ipsec.IntegrityCheckMethod
                    DHGroup                          = $ipsec.DHGroup
                    PfsGroup                         = $ipsec.PfsGroup
                    Force                            = $true
                    ErrorAction                      = 'Stop'
                }
                if ($conn.AllUserConnection) { $ipsecParams.AllUserConnection = $true }
                Set-VpnConnectionIPsecConfiguration @ipsecParams
            }

            # ── Restore routes ─────────────────────────────────────────────
            if ($conn.Routes -and $conn.Routes.Count -gt 0) {
                foreach ($route in $conn.Routes) {
                    try {
                        $routeParams = @{
                            ConnectionName    = $name
                            DestinationPrefix = $route.DestinationPrefix
                            RouteMetric       = $route.RouteMetric
                            ErrorAction       = 'Stop'
                        }
                        if ($conn.AllUserConnection) { $routeParams.AllUserConnection = $true }
                        Add-VpnConnectionRoute @routeParams
                    }
                    catch {
                        Write-Warning "  Could not add route $($route.DestinationPrefix) to '$name': $_"
                    }
                }
            }

            Write-Host "    OK: $name" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to import '$name': $_"
        }
    }

    Write-Host "`nImport complete." -ForegroundColor Green
}

#endregion

#region ── Entry point ─────────────────────────────────────────────────────────

switch ($Mode) {
    'Export' {
        Export-VpnConnections -FilePath $FilePath -IncludeAllUser $AllUserConnection.IsPresent
    }
    'Import' {
        Import-VpnConnections -FilePath $FilePath
    }
}

#endregion
