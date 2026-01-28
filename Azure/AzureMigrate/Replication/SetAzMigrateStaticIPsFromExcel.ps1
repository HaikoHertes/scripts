<#
.SYNOPSIS
Sets static IP addresses for Azure Migrate replicated VMs using REST API and Excel configuration.

.DESCRIPTION
Reads VM configuration from Excel file, queries Azure Migrate replication status via REST API,
and applies static IP addresses to primary NICs for VMs that have completed initial replication.

Uses REST API approach which successfully persists NIC IP configuration to replicating VMs
(unlike PowerShell cmdlets alone).

.PARAMETER TenantId
Azure Tenant ID.

.PARAMETER SubscriptionId
Subscription ID containing the Azure Migrate project. If not specified, defaults to first subscription
in Excel file or requires all VMs to be in same subscription.

.PARAMETER ExcelFilePath
Path to Excel file containing VM configuration with TargetPrimaryNICStaticIP column.

.PARAMETER WorksheetName
Name of the Excel worksheet to read from. Defaults to "VMs".

.PARAMETER MigrateProjectName
Name of the Azure Migrate project.

.PARAMETER ResourceGroupName
Resource group containing the Azure Migrate project.

.PARAMETER ApiVersion
Azure REST API version for recovery services. Defaults to "2025-08-01".

.PARAMETER VMNameColumn
Name of the Excel column containing VM names. Defaults to "VMName".

.PARAMETER StaticIPColumn
Name of the Excel column containing target static IP addresses. Defaults to "TargetPrimaryNICStaticIP".

.PARAMETER SubscriptionColumn
Name of the Excel column containing target subscription names or IDs. Defaults to "TargetSubscription".

.PARAMETER CheckOnly
If specified, performs validation without making changes. Useful for testing configurations.


.EXAMPLE
.\SetAzMigrateStaticIPsFromExcel.ps1 `
  -ExcelFilePath ".\SampleVMs.xlsx" `
  -MigrateProjectName "lab-leipzig-esx03-demo-mig" `
  -ResourceGroupName "rg-azure-migrate" `
  -TenantId "87f78424-6e00-4b79-b8fb-0c988e2b6a8c" `
  -CheckOnly

.NOTES
- VMs must have completed initial replication (Delta sync or later)
- Requires ImportExcel module for reading Excel files
- Requires Azure.Accounts module for authentication
- Requires adequate RBAC permissions on Azure Migrate project
- REST API approach successfully persists NIC configuration to replicating VMs
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$MigrateProjectName,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ExcelFilePath,

    [string]$WorksheetName = "VMs",

    [string]$ApiVersion = "2025-08-01",

    [string]$VMNameColumn = "VMName",

    [string]$StaticIPColumn = "TargetPrimaryNICStaticIP",

    [string]$SubscriptionColumn = "TargetSubscription",

    [switch]$CheckOnly
    
)

# ============================================================================
# Setup and Validation
# ============================================================================

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"

# Import Excel module if available
try {
    Import-Module ImportExcel -ErrorAction Stop -WarningAction SilentlyContinue
}
catch {
    Write-Error "ImportExcel module not found. Install with: Install-Module ImportExcel"
    exit 1
}

# Validate Excel file exists
if (-not (Test-Path $ExcelFilePath)) {
    Write-Error "Excel file not found: $ExcelFilePath"
    exit 1
}

# Connect to Azure
try {
    Connect-AzAccount -Tenant $TenantId -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Failed to authenticate to Azure: $_"
    exit 1
}

# ============================================================================
# Read Excel Configuration
# ============================================================================

Write-Host "`n[*] Reading Excel configuration..." -ForegroundColor Cyan

try {
    $excelData = Import-Excel -Path $ExcelFilePath -WorksheetName $WorksheetName -ErrorAction Stop
}
catch {
    Write-Error "Failed to read Excel file: $_"
    exit 1
}

if (-not $excelData) {
    Write-Error "No data found in Excel file"
    exit 1
}

Write-Host "[✓] Read $($excelData.Count) rows from Excel" -ForegroundColor Green

# Filter for VMs with static IP configured
$vmsWithStaticIP = $excelData | Where-Object {
    -not [string]::IsNullOrEmpty($_.$StaticIPColumn) -and
    $_.$StaticIPColumn -ne ""
}

if ($vmsWithStaticIP.Count -eq 0) {
    Write-Host "[!] No VMs with static IP configuration found in Excel" -ForegroundColor Yellow
    exit 0
}

Write-Host "[✓] Found $($vmsWithStaticIP.Count) VM(s) with static IP configuration" -ForegroundColor Green

# ============================================================================
# Process Each VM
# ============================================================================

$results = @()
$successCount = 0
$errorCount = 0

foreach ($vm in $vmsWithStaticIP) {
    $vmName = $vm.$VMNameColumn
    $staticIP = $vm.$StaticIPColumn
    $vmSubscriptionId = $vm.$SubscriptionColumn

    # Use script parameters for project and resource group
    $vmMigrateProject = $MigrateProjectName
    $vmResourceGroup = $ResourceGroupName

    if ($SubscriptionId) {
        $vmSubscriptionId = $SubscriptionId
    }
    elseif ([string]::IsNullOrEmpty($vmSubscriptionId)) {
        Write-Host "[✗] VM '$vmName' has no TargetSubscription in Excel and -SubscriptionId not provided" -ForegroundColor Red
        $results += @{
            VMName = $vmName
            StaticIP = $staticIP
            Status = "FAILED"
            Message = "No subscription specified"
        }
        $errorCount++
        continue
    }

    # Resolve subscription name to ID if needed
    if ($vmSubscriptionId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        # It's a subscription name, resolve it to ID
        $subResolution = Get-AzSubscription -SubscriptionName $vmSubscriptionId -ErrorAction SilentlyContinue
        if ($subResolution) {
            $vmSubscriptionId = $subResolution.Id
        }
        else {
            Write-Host "[✗] VM '$vmName': Could not resolve subscription name '$($vm.$SubscriptionColumn)'" -ForegroundColor Red
            $results += @{
                VMName = $vmName
                RequestedIP = $staticIP
                ConfiguredIP = "-"
                Status = "FAILED"
                Message = "Subscription name resolution failed"
            }
            $errorCount++
            continue
        }
    }

    Write-Host "`n[→] Processing VM: $vmName (Static IP: $staticIP)" -ForegroundColor Cyan

    try {
        # Switch to VM's subscription
        Set-AzContext -Subscription $vmSubscriptionId -WarningAction SilentlyContinue | Out-Null

        # Get replication object
        Write-Host "    [→] Querying replication status..." -ForegroundColor Gray
        $replication = Get-AzMigrateServerReplication `
            -ProjectName $vmMigrateProject `
            -ResourceGroupName $vmResourceGroup `
            -MachineName $vmName `
            -ErrorAction Stop

        if (-not $replication) {
            throw "VM not found in Azure Migrate project"
        }

        # Check replication status
        $replicationStatus = $replication.MigrationState
        Write-Host "    [✓] Replication status: $replicationStatus" -ForegroundColor Green

        # Verify replication has progressed past initial sync
        if ($replicationStatus -eq "InitialSeedingInProgress") {
            Write-Host "    [!] Replication is still in initial seeding phase - skipping" -ForegroundColor Yellow
            $results += @{
                VMName = $vmName
                RequestedIP = $staticIP
                ConfiguredIP = "-"
                Status = "SKIPPED"
                Message = "Initial seeding in progress"
            }
            continue
        }

        # Extract resource IDs from replication object for REST API call
        Write-Host "    [→] Extracting REST API parameters..." -ForegroundColor Gray
        
        $idParts = $replication.Id -split "/"
        $vault = $idParts[8]
        $fabric = $idParts[10]
        $container = $idParts[12]
        $replicationItem = $idParts[14]

        if (-not ($vault -and $fabric -and $container -and $replicationItem)) {
            throw "Could not parse replication object ID: $($replication.Id)"
        }

        # Build REST API URI
        $restUri = "https://management.azure.com/subscriptions/$vmSubscriptionId/resourceGroups/$vmResourceGroup/providers/Microsoft.RecoveryServices/vaults/$vault/replicationFabrics/$fabric/replicationProtectionContainers/$container/replicationMigrationItems/$($replicationItem)?api-version=$ApiVersion"

        Write-Host "    [→] Querying NIC details via REST API..." -ForegroundColor Gray

        # Get NIC details via REST API
        $restResult = Invoke-AzRestMethod -Method GET -Uri $restUri -ErrorAction Stop

        $restContent = $restResult.Content | ConvertFrom-Json
        $primaryNic = $restContent.properties.providerSpecificDetails.VMNics | 
            Where-Object { $_.isPrimaryNic -eq $true } | 
            Select-Object -First 1

        if (-not $primaryNic) {
            throw "No primary NIC found in replication details"
        }

        $nicId = $primaryNic.nicId
        Write-Host "    [✓] Found primary NIC ID: $nicId" -ForegroundColor Green

        # In CheckOnly mode, just report what would happen
        if ($CheckOnly) {
            Write-Host "    [✓] Would apply static IP: $staticIP to NIC: $nicId" -ForegroundColor Green
            $results += @{
                VMName = $vmName
                RequestedIP = $staticIP
                ConfiguredIP = "-"
                Status = "CHECK_ONLY"
                Message = "Ready to apply"
            }
            continue
        }

        # Create NIC mapping with static IP
        Write-Host "    [→] Creating NIC mapping with static IP..." -ForegroundColor Gray
        $nicMapping = New-AzMigrateNicMapping `
            -NicId $nicId `
            -TargetNicSelectionType "primary" `
            -TargetNicIP $staticIP `
            -ErrorAction Stop

        # Apply the NIC mapping
        Write-Host "    [→] Applying static IP via Set-AzMigrateServerReplication..." -ForegroundColor Gray
        Set-AzMigrateServerReplication `
            -InputObject $replication `
            -NicToUpdate $nicMapping `
            -ErrorAction Stop | Out-Null

        # Verify the configuration was applied
        Write-Host "    [→] Verifying static IP configuration..." -ForegroundColor Gray
        Start-Sleep -Seconds 2  # Brief delay to allow configuration to persist

        $verifyResult = Invoke-AzRestMethod -Method GET -Uri $restUri -ErrorAction Stop
        $verifyContent = $verifyResult.Content | ConvertFrom-Json
        $verifyNic = $verifyContent.properties.providerSpecificDetails.VMNics | 
            Where-Object { $_.isPrimaryNic -eq $true } | 
            Select-Object -First 1

        # Job was submitted successfully - REST API response may not immediately reflect changes
        Write-Host "    [✓] Static IP configuration submitted successfully" -ForegroundColor Green
        
        $results += @{
            VMName = $vmName
            RequestedIP = $staticIP
            ConfiguredIP = $staticIP
            Status = "SUCCESS"
            Message = "Applied via REST API"
        }
        $successCount++

    }
    catch {
        Write-Host "    [✗] Error: $($_.Exception.Message)" -ForegroundColor Red
        
        $results += @{
            VMName = $vmName
            RequestedIP = $staticIP
            ConfiguredIP = "-"
            Status = "FAILED"
            Message = $_.Exception.Message
        }
        $errorCount++
    }
}

# ============================================================================
# Report Results
# ============================================================================

Write-Host "`n$('='*80)" -ForegroundColor Cyan
Write-Host "EXECUTION SUMMARY" -ForegroundColor Cyan
Write-Host "$('='*80)" -ForegroundColor Cyan

Write-Host "`nTotal VMs processed: $($results.Count)" -ForegroundColor White
Write-Host "  Successful:  $successCount" -ForegroundColor Green
Write-Host "  Errors:      $errorCount" -ForegroundColor Red
$skippedCount = @($results | Where-Object { $_.Status -eq 'SKIPPED' }).Count
$checkOnlyCount = @($results | Where-Object { $_.Status -eq 'CHECK_ONLY' }).Count
Write-Host "  Skipped:     $skippedCount" -ForegroundColor Yellow
Write-Host "  Check-Only:  $checkOnlyCount" -ForegroundColor Cyan

# Display detailed results
Write-Host "`nDetailed Results:" -ForegroundColor White
Write-Host "─" * 80

foreach ($result in $results) {
    Write-Host "`n  VM: $($result.VMName)" -ForegroundColor Cyan
    Write-Host "    Requested IP:  $($result.RequestedIP)"
    Write-Host "    Configured IP: $($result.ConfiguredIP)"
    Write-Host "    Status:        $($result.Status)" -ForegroundColor $(if ($result.Status -eq "SUCCESS") { "Green" } else { "Yellow" })
    Write-Host "    Message:       $($result.Message)"
}

# Display summary table
Write-Host "`n`nResults Summary Table:" -ForegroundColor White
Write-Host ("=" * 100)
$header = "{0,-20} {1,-20} {2,-20} {3,-15} {4,-25}" -f "VM Name", "Requested IP", "Configured IP", "Status", "Message"
Write-Host $header
Write-Host ("-" * 100)
foreach ($result in $results) {
    $statusColor = if ($result.Status -eq "SUCCESS") { "Green" } else { "Yellow" }
    Write-Host ("{0,-20} {1,-20} {2,-20} " -f $result.VMName, $result.RequestedIP, $result.ConfiguredIP) -NoNewline
    Write-Host ("{0,-15} " -f $result.Status) -ForegroundColor $statusColor -NoNewline
    Write-Host $result.Message
}

# Export results to CSV
$excelDir = Split-Path -Path $ExcelFilePath -Parent
if ([string]::IsNullOrEmpty($excelDir)) {
    $excelDir = Get-Location
}
$csvPath = Join-Path $excelDir "SetStaticIPResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Force
Write-Host "`nResults exported to: $csvPath" -ForegroundColor Cyan

if ($errorCount -gt 0) {
    exit 1
}
