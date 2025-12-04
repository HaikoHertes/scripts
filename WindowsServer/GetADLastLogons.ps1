<#
.SYNOPSIS
Ermittelt letzte Logins aus den Security-Logs aller Domain Controller.

.PARAMETER User
SAM-Accountname eines einzelnen Benutzers.

.PARAMETER MaxLogons
Anzahl der Logins, die angezeigt werden sollen (Standard: 30).

.PARAMETER MaxAgeDays
Maximal zurückliegender Zeitraum in Tagen, der betrachtet werden soll (Standard: 30 Tage).

.PARAMETER MaxEvents
Maximale Anzahl Events, die pro DC eingelesen werden (Standard: 1000).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$User,

    [Parameter(Mandatory = $false)]
    [int]$MaxLogons = 30,

    [Parameter(Mandatory = $false)]
    [int]$MaxAgeDays = 30,

    [Parameter(Mandatory = $false)]
    [int]$MaxEvents = 1000
)

Write-Host "-----------------------------------------------"
Write-Host "   Logon-Analyse startet..."
Write-Host "-----------------------------------------------`n"

# --- Mapping der relevanten Logon-Typen --------------------------------------
# Hinweis:
#  - 2  = Interactive (lokale Anmeldung)
#  - 3  = Network (z. B. SMB, Dienste, ggf. auch VPN)
#  - 10 = RemoteInteractive (RDP)
#
# Wenn du NUR VPN-Logons willst, müsstest du zusätzlich z. B. nach Workstation/Gateway-Namen filtern.
$LogonTypeMap = @{
    '2'  = 'Interactive'
    '3'  = 'Network'
    '10' = 'RemoteInteractive (RDP)'
}
$AllowedTypes = '2','3','10'

# Startzeitpunkt für die Auswertung (zeitliche Eingrenzung)
if ($MaxAgeDays -gt 0) {
    $StartTime = (Get-Date).AddDays(-$MaxAgeDays)
} else {
    # Falls jemand 0 oder negativ angibt: kein Zeitfilter
    $StartTime = $null
}

# --- Active Directory Modul ---------------------------------------------------
Write-Host "[1/5] Lade ActiveDirectory-Modul..."
try {
    if (-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
        throw "Das ActiveDirectory-Modul ist nicht installiert."
    }
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "   ✓ Modul erfolgreich geladen.`n"
}
catch {
    Write-Error "Konnte das ActiveDirectory-Modul nicht laden: $_"
    return
}

# --- Domain Controller finden -------------------------------------------------
Write-Host "[2/5] Ermittele Domain Controller..."
try {
    $DCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
    if ($DCs.Count -eq 0) { throw "Keine Domain Controller gefunden." }

    Write-Host "   ✓ Gefundene DCs: $($DCs -join ', ')`n"
}
catch {
    Write-Error "Fehler beim Ermitteln der Domain Controller: $_"
    return
}

# --- Logon-Events auslesen ----------------------------------------------------
Write-Host "[3/5] Lese Logon-Ereignisse (Event-ID 4624) von allen DCs..."
if ($StartTime) {
    Write-Host "   → Zeitraum: letzte $MaxAgeDays Tage (ab $($StartTime.ToString('yyyy-MM-dd HH:mm:ss')))"
} else {
    Write-Host "   → Kein Zeitfilter (es wird der gesamte Log betrachtet, begrenzt durch -MaxEvents)."
}
Write-Host "   → MaxEvents pro DC: $MaxEvents"
$allLogons = @()

foreach ($dc in $DCs) {
    Write-Host "   → Verbinde mit '$dc' und lese Security-Log..."

    try {
        $filter = @{
            LogName = 'Security'
            Id      = 4624
        }
        if ($StartTime) {
            $filter.StartTime = $StartTime
        }

        $events = Get-WinEvent -ComputerName $dc -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop

        Write-Host "     ✓ $($events.Count) Events von $dc eingelesen."
    }
    catch {
        Write-Warning "     ⚠ Fehler beim Lesen des Security-Logs von '$dc': $_"
        continue
    }

    foreach ($event in $events) {
        $xml = [xml]$event.ToXml()
        $data = $xml.Event.EventData.Data

        $targetUser   = ($data | Where-Object { $_.Name -eq 'TargetUserName' }).'#text'
        $targetDomain = ($data | Where-Object { $_.Name -eq 'TargetDomainName' }).'#text'
        $workstation  = ($data | Where-Object { $_.Name -eq 'WorkstationName' }).'#text'
        $logonType    = ($data | Where-Object { $_.Name -eq 'LogonType' }).'#text'

        # Maschinenkonten überspringen
        if ($targetUser -and $targetUser.EndsWith('$')) { continue }

        # Nur gewünschte Logon-Typen
        if ($logonType -notin $AllowedTypes) { continue }

        # Benutzerfilter
        if ($User -and $targetUser -ne $User) { continue }

        # Logon-Typ übersetzen
        $logonTypeReadable = $LogonTypeMap[$logonType]

        $allLogons += [PSCustomObject]@{
            TimeStamp   = $event.TimeCreated
            User        = $targetUser
            Domain      = $targetDomain
            LogonDC     = $dc
            Workstation = $workstation
            LogonType   = $logonTypeReadable
        }
    }
}

Write-Host "`n   ✓ Auslesen aller DCs abgeschlossen."
Write-Host "     Insgesamt eingelesene Logins (nach Filterung): $($allLogons.Count)`n"

if ($allLogons.Count -eq 0) {
    Write-Host "Keine Logins gefunden. Vorgang beendet."
    return
}

# --- Prüfen, ob MaxEvents begrenzender Faktor war -----------------------------
if ($StartTime -and $allLogons.Count -gt 0) {
    $oldestEvent = $allLogons | Sort-Object TimeStamp | Select-Object -First 1

    if ($oldestEvent.TimeStamp -gt $StartTime.AddHours(8)) {
        Write-Host "Hinweis:"
        Write-Host "   Das älteste gefundene Logon-Event ist vom $($oldestEvent.TimeStamp.ToString('yyyy-MM-dd HH:mm:ss'))."
        Write-Host "   Dies ist mehr als 8 Stunden neuer als der gewünschte Startzeitpunkt ($($StartTime.ToString('yyyy-MM-dd HH:mm:ss')))."
        Write-Host "   Vermutlich war der Parameter -MaxEvents (pro DC: $MaxEvents) der begrenzende Faktor und nicht -MaxAgeDays.`n"
    }
}

# --- Ergebnisse verarbeiten ---------------------------------------------------
Write-Host "[4/5] Verarbeite Ergebnisse..."

if ($User) {
    Write-Host "   → Filtere nach Benutzer: $User"
    $result = $allLogons |
        Where-Object { $_.User -eq $User } |
        Sort-Object TimeStamp -Descending
}
else {
    Write-Host "   → Zeige letzte $MaxLogons Logins an."
    $result = $allLogons |
        Sort-Object TimeStamp -Descending |
        Select-Object -First $MaxLogons
}

Write-Host "   ✓ Verarbeitung abgeschlossen.`n"

if ($result.Count -eq 0) {
    Write-Host "Keine passenden Logins gefunden."
    return
}

# --- Ausgabe ------------------------------------------------------------------
Write-Host "[5/5] Ergebnisse:"
Write-Host "-----------------------------------------------"

$result |
    Select-Object @{
        Name       = 'Datum';
        Expression = { $_.TimeStamp.ToString('yyyy-MM-dd') }
    }, @{
        Name       = 'Uhrzeit';
        Expression = { $_.TimeStamp.ToString('HH:mm:ss') }
    }, User, LogonType, LogonDC, Workstation |
    Format-Table -AutoSize

Write-Host "-----------------------------------------------"
Write-Host "Fertig!"
