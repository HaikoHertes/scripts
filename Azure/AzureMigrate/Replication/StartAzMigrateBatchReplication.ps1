param(
    [Parameter(Mandatory = $true)]
    [string]$ExcelFilePath,
    
    [Parameter(Mandatory = $false)]
    [string]$SheetName = "VMs",
    
    [Parameter(Mandatory = $false)]
    [switch]$CheckOnly,
    
    [Parameter(Mandatory = $false)]
    [string]$TargetSubscriptionId,
    
    [Parameter(Mandatory = $true)]
    [string]$TenantId,
    
    [Parameter(Mandatory = $true)]
    [string]$TargetRegion,
    
    [Parameter(Mandatory = $false)]
    [int]$Wave = 0  # 0 = all waves, otherwise filter by specific wave
)

# Script configuration
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Header {
    param([string]$Message)
    Write-Host "`n========== $Message ==========" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[✓] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[✗] $Message" -ForegroundColor Red
}

function Test-AzureAuthentication {
    param([string]$TenantId)
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        
        # Check if context exists and is in the correct tenant (if TenantId is specified)
        if ($context) {
            if ($TenantId) {
                # Verify we're in the correct tenant
                if ($context.Tenant.Id -eq $TenantId) {
                    Write-Success "Already authenticated as $($context.Account.Id) in tenant $($context.Tenant.Id)"
                    return $true
                }
                else {
                    Write-Host "Current context is in tenant $($context.Tenant.Id), but need to connect to tenant $TenantId"
                    Write-Host "Switching to required tenant..."
                    Disconnect-AzAccount -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null
                    Write-Success "Successfully authenticated to tenant $TenantId"
                    return $true
                }
            }
            else {
                Write-Success "Already authenticated as $($context.Account.Id)"
                return $true
            }
        }
        else {
            Write-Host "No valid Azure authentication context found. Attempting login..."
            if ($TenantId) {
                Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null
                Write-Success "Successfully authenticated to tenant $TenantId"
            }
            else {
                Connect-AzAccount -ErrorAction Stop | Out-Null
                Write-Success "Successfully authenticated to Azure"
            }
            return $true
        }
    }
    catch {
        Write-Error "Failed to authenticate to Azure: $_"
        return $false
    }
}

function Get-SubscriptionId {
    param([string]$SubscriptionIdentifier)
    
    try {
        # If it looks like a GUID, try to use it directly
        if ($SubscriptionIdentifier -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            return $SubscriptionIdentifier
        }
        
        # Otherwise, try to resolve by name (suppress warnings about inaccessible tenants)
        $subscription = Get-AzSubscription -SubscriptionName $SubscriptionIdentifier -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        if ($subscription) {
            Write-Success "Resolved subscription '$SubscriptionIdentifier' to ID: $($subscription.Id)"
            return $subscription.Id
        }
        
        # If not found by name, return the original (might be an ID that failed validation)
        Write-Warning "Could not resolve subscription name '$SubscriptionIdentifier', using as-is"
        return $SubscriptionIdentifier
    }
    catch {
        Write-Warning "Error resolving subscription '$SubscriptionIdentifier': $_"
        return $SubscriptionIdentifier
    }
}

function Confirm-ResourceExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceName,
        
        [Parameter(Mandatory = $false)]
        [string]$ResourceGroupName,
        
        [Parameter(Mandatory = $false)]
        [string]$SubscriptionId
    )
    
    try {
        $params = @{
            ResourceType = $ResourceType
            Name         = $ResourceName
        }
        
        if ($ResourceGroupName) {
            $params["ResourceGroupName"] = $ResourceGroupName
        }
        
        if ($SubscriptionId) {
            $contextSet = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
        }
        
        $resource = Get-AzResource @params -ErrorAction SilentlyContinue
        
        return $null -ne $resource
    }
    catch {
        return $false
    }
}

function Test-AzureMigrateVMs {
    param(
        [Parameter(Mandatory = $true)]
        [array]$VMConfigs,
        
        [Parameter(Mandatory = $true)]
        [string]$MigrateProjectName,
        
        [Parameter(Mandatory = $true)]
        [string]$MigrateProjectResourceGroup
    )
    
    Write-Host "`nValidating VMs in Azure Migrate Inventory..."
    $missingVMs = @()
    $foundVMs = @()
    
    # Get unique VM names
    $uniqueVMs = $VMConfigs.VMName | Select-Object -Unique
    
    # Get all servers from the project
    try {
        $allServers = Get-AzMigrateDiscoveredServer -ProjectName $MigrateProjectName -ResourceGroupName $MigrateProjectResourceGroup -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to retrieve servers from Azure Migrate project: $_"
        return @{
            FoundVMs   = @()
            MissingVMs = $uniqueVMs
        }
    }
    
    # Check each VM from Excel against the discovered servers
    foreach ($vmName in $uniqueVMs) {
        $server = $allServers | Where-Object { $_.DisplayName -eq $vmName }
        
        if ($server) {
            Write-Success "VM found in Azure Migrate inventory: $vmName"
            $foundVMs += $vmName
        }
        else {
            Write-Error "VM not found in Azure Migrate inventory: $vmName"
            $missingVMs += $vmName
        }
    }
    
    return @{
        FoundVMs   = $foundVMs
        MissingVMs = $missingVMs
    }
}

function Initialize-ReplicationInfrastructureForSubscription {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionName,
        
        [Parameter(Mandatory = $true)]
        [string]$MigrateProjectName,
        
        [Parameter(Mandatory = $true)]
        [string]$MigrateProjectResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetRegion,
        
        [Parameter(Mandatory = $false)]
        [switch]$CheckOnly
    )
    
    Write-Host "`nChecking replication infrastructure for subscription: $SubscriptionName" -ForegroundColor Cyan
    
    # Switch to target subscription
    Set-AzContext -SubscriptionId $SubscriptionId -WarningAction SilentlyContinue | Out-Null
    
    try {
        # Check if infrastructure already exists
        $replicationFabric = Get-AzMigrateReplicationFabric -ResourceGroupName $MigrateProjectResourceGroup -ResourceName $MigrateProjectName -ErrorAction Stop
        if ($replicationFabric) {
            Write-Success "Replication infrastructure already initialized in subscription: $SubscriptionName"
            return $true
        }
    }
    catch {
        # Infrastructure not found, will need to initialize
    }
    
    # If in CheckOnly mode, don't try to initialize
    if ($CheckOnly) {
        Write-Warning "Replication infrastructure is not initialized in subscription: $SubscriptionName (CheckOnly mode - skipping initialization)"
        return $false
    }
    
    Write-Warning "Replication infrastructure is not initialized in subscription: $SubscriptionName"
    Write-Host "`nInitializing replication infrastructure..."
    Write-Host "  Subscription: $SubscriptionName ($SubscriptionId)"
    Write-Host "  Project: $MigrateProjectName"
    Write-Host "  Resource Group: $MigrateProjectResourceGroup"
    Write-Host "  Target Region: $TargetRegion"
    Write-Host "  Scenario: agentlessVMware"
    Write-Host ""
    
    try {
        Initialize-AzMigrateReplicationInfrastructure `
            -ResourceGroupName $MigrateProjectResourceGroup `
            -ProjectName $MigrateProjectName `
            -Scenario 'agentlessVMware' `
            -TargetRegion $TargetRegion `
            -WarningAction SilentlyContinue `
            -ErrorAction Stop
        
        Write-Success "Replication infrastructure initialized successfully in subscription: $SubscriptionName"
        Write-Host "Waiting 30 seconds for infrastructure to stabilize..." -ForegroundColor Gray
        Start-Sleep -Seconds 30
        return $true
    }
    catch {
        Write-Error "Failed to initialize replication infrastructure in subscription: $SubscriptionName"
        Write-Error "Error: $_"
        Write-Host "`nPossible reasons:" -ForegroundColor Yellow
        Write-Host "  - The Azure Migrate appliance may not be properly configured"
        Write-Host "  - Required permissions may be missing"
        Write-Host "  - Try initializing manually from the Azure Portal"
        return $false
    }
}

function Test-AzureResources {
    param(
        [Parameter(Mandatory = $true)]
        [array]$VMConfigs,
        
        [Parameter(Mandatory = $true)]
        [string]$MigrateProjectName,
        
        [Parameter(Mandatory = $true)]
        [string]$MigrateProjectResourceGroup,
        
        [Parameter(Mandatory = $true)]
        [string]$MigrateProjectSubscriptionId
    )
    
    Write-Header "Validating Azure Resources"
    
    $missingResources = @()
    $validatedResources = @()
    
    # Resolve migration project subscription ID
    $resolvedMigrateSubscriptionId = Get-SubscriptionId -SubscriptionIdentifier $MigrateProjectSubscriptionId
    
    # Set context to migration project subscription (suppress warnings about inaccessible tenants)
    try {
        Set-AzContext -SubscriptionId $resolvedMigrateSubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
        Write-Success "Connected to migration project subscription: $MigrateProjectSubscriptionId"
    }
    catch {
        Write-Error "Failed to connect to migration project subscription $MigrateProjectSubscriptionId : $_"
        return $null
    }
    
    # Collect unique target subscriptions
    $uniqueTargetSubscriptions = $VMConfigs.TargetSubscription | Select-Object -Unique
    
    # Validate resources per target subscription
    foreach ($targetSubId in $uniqueTargetSubscriptions) {
        $resolvedTargetSubId = Get-SubscriptionId -SubscriptionIdentifier $targetSubId
        
        try {
            Set-AzContext -SubscriptionId $resolvedTargetSubId -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
            Write-Success "Connected to target subscription: $targetSubId"
        }
        catch {
            Write-Error "Failed to connect to target subscription $targetSubId : $_"
            $missingResources += "Target Subscription: $targetSubId"
            continue
        }
        
        # Get VMs for this subscription
        $vmsInSubscription = $VMConfigs | Where-Object { $_.TargetSubscription -eq $targetSubId }
        
        # Collect unique resources for this subscription
        $uniqueRGs = $vmsInSubscription.TargetResourceGroup | Select-Object -Unique
        $uniqueVNets = $vmsInSubscription | Select-Object -Unique -Property TargetVirtualNetwork, TargetVNetResourceGroup
        $uniqueStorageAccounts = $vmsInSubscription | Select-Object -Unique -Property TargetStorageAccount, TargetStorageAccountResourceGroup
        
        # Validate Resource Groups
        Write-Host "`nValidating Resource Groups in subscription $targetSubId..."
        foreach ($rg in $uniqueRGs) {
            try {
                $rgExists = Get-AzResourceGroup -Name $rg -ErrorAction Stop
                Write-Success "Resource Group found: $rg"
                $validatedResources += "RG: $rg"
            }
            catch {
                Write-Error "Resource Group not found: $rg"
                $missingResources += "Resource Group: $rg"
            }
        }
        
        # Validate Virtual Networks
        Write-Host "`nValidating Virtual Networks in subscription $targetSubId..."
        foreach ($vnetConfig in $uniqueVNets) {
            try {
                $vnet = Get-AzVirtualNetwork -Name $vnetConfig.TargetVirtualNetwork -ResourceGroupName $vnetConfig.TargetVNetResourceGroup -ErrorAction Stop
                Write-Success "Virtual Network found: $($vnetConfig.TargetVirtualNetwork) in RG: $($vnetConfig.TargetVNetResourceGroup)"
                $validatedResources += "VNet: $($vnetConfig.TargetVirtualNetwork)"
                
                # Validate all subnets used by VMs in this VNet
                $subnetsForVNet = $vmsInSubscription | Where-Object { $_.TargetVirtualNetwork -eq $vnetConfig.TargetVirtualNetwork } | Select-Object -ExpandProperty TargetSubnet -Unique
                foreach ($subnetName in $subnetsForVNet) {
                    try {
                        $subnet = Get-AzVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -ErrorAction Stop
                        Write-Success "Subnet found: $subnetName"
                        $validatedResources += "Subnet: $($vnetConfig.TargetVirtualNetwork)/$subnetName"
                    }
                    catch {
                        Write-Error "Subnet not found: $subnetName in VNet: $($vnetConfig.TargetVirtualNetwork)"
                        $missingResources += "Subnet: $subnetName"
                    }
                }
            }
            catch {
                Write-Error "Virtual Network not found: $($vnetConfig.TargetVirtualNetwork) in RG: $($vnetConfig.TargetVNetResourceGroup)"
                $missingResources += "VNet: $($vnetConfig.TargetVirtualNetwork)"
            }
        }
        
        # Validate Storage Accounts
        Write-Host "`nValidating Storage Accounts in subscription $targetSubId..."
        foreach ($storageConfig in $uniqueStorageAccounts) {
            try {
                $storage = Get-AzStorageAccount -Name $storageConfig.TargetStorageAccount -ResourceGroupName $storageConfig.TargetStorageAccountResourceGroup -ErrorAction Stop
                Write-Success "Storage Account found: $($storageConfig.TargetStorageAccount) in RG: $($storageConfig.TargetStorageAccountResourceGroup)"
                $validatedResources += "Storage: $($storageConfig.TargetStorageAccount)"
            }
            catch {
                Write-Error "Storage Account not found: $($storageConfig.TargetStorageAccount) in RG: $($storageConfig.TargetStorageAccountResourceGroup)"
                $missingResources += "Storage Account: $($storageConfig.TargetStorageAccount)"
            }
        }
    }
    
    # Validate VMs in Azure Migrate Inventory (switch to migration project subscription first)
    Set-AzContext -SubscriptionId $resolvedMigrateSubscriptionId -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
    $vmValidation = Test-AzureMigrateVMs -VMConfigs $VMConfigs -MigrateProjectName $MigrateProjectName -MigrateProjectResourceGroup $MigrateProjectResourceGroup
    if ($vmValidation.FoundVMs.Count -gt 0) {
        $validatedResources += @($vmValidation.FoundVMs | ForEach-Object { "VM: $_" })
    }
    if ($vmValidation.MissingVMs.Count -gt 0) {
        $missingResources += @($vmValidation.MissingVMs | ForEach-Object { "VM not in Azure Migrate inventory: $_" })
    }
    
    # Summary
    Write-Header "Validation Summary"
    Write-Host "Validated Resources:"
    $validatedResources | ForEach-Object { Write-Success $_ }
    
    if ($missingResources.Count -gt 0) {
        Write-Host "`nMissing Resources (CRITICAL):"
        $missingResources | ForEach-Object { Write-Error $_ }
        return $false
    }
    else {
        Write-Success "All required resources exist!"
        return $true
    }
}

# ============================================================================
# Main Script
# ============================================================================

Write-Header "Azure Migrate Batch Replication Script"

# Validate input file
if (-not (Test-Path $ExcelFilePath)) {
    Write-Error "Excel file not found: $ExcelFilePath"
    exit 1
}

Write-Success "Excel file found: $ExcelFilePath"

# Import Excel module
try {
    Import-Module ImportExcel -ErrorAction Stop -Verbose:$false
    Write-Success "ImportExcel module loaded"
}
catch {
    Write-Error "Failed to import ImportExcel module: $_"
    Write-Host "Install with: Install-Module ImportExcel -Force"
    exit 1
}

# Import Az.Migrate module
try {
    Import-Module Az.Migrate -ErrorAction Stop -Verbose:$false
    Write-Success "Az.Migrate module loaded"
}
catch {
    Write-Error "Failed to import Az.Migrate module: $_"
    Write-Host "Install with: Install-Module Az.Migrate -Force"
    exit 1
}

# Import Az.Accounts module
try {
    Import-Module Az.Accounts -ErrorAction Stop -Verbose:$false
    Write-Success "Az.Accounts module loaded"
}
catch {
    Write-Error "Failed to import Az.Accounts module: $_"
    exit 1
}

# Read Excel file
Write-Header "Reading Excel Configuration"
try {
    $vmConfigs = Import-Excel -Path $ExcelFilePath -WorksheetName $SheetName -ErrorAction Stop
    Write-Success "Read $($vmConfigs.Count) VM configurations from Excel"
    
    if ($vmConfigs.Count -eq 0) {
        Write-Error "No VM configurations found in Excel"
        exit 1
    }
}
catch {
    Write-Error "Failed to read Excel file: $_"
    exit 1
}

# Filter by wave if specified
if ($Wave -gt 0) {
    $vmConfigs = $vmConfigs | Where-Object { $_.Wave -eq $Wave }
    Write-Success "Filtered to Wave $($Wave): $($vmConfigs.Count) VMs"
}

if ($vmConfigs.Count -eq 0) {
    Write-Warning "No VMs found for wave $Wave"
    exit 0
}

# Display VMs to be processed
Write-Host "`nVMs to be processed:"
$vmConfigs | ForEach-Object {
    Write-Host "  - Wave $($_.Wave): $($_.VMName) -> $($_.TargetVMName) (Size: $($_.TargetVMSize))"
}

# Validate all VMs have a target subscription
$vmMissingSubscription = $vmConfigs | Where-Object { [string]::IsNullOrEmpty($_.TargetSubscription) }
if ($vmMissingSubscription) {
    Write-Error "The following VMs are missing TargetSubscription: $($vmMissingSubscription.VMName -join ', ')"
    exit 1
}

# Use the first VM's subscription for the Migrate project if not provided
if (-not $TargetSubscriptionId) {
    $TargetSubscriptionId = $vmConfigs[0].TargetSubscription
}

# Ensure Azure authentication
Write-Header "Azure Authentication"
$authSuccess = Test-AzureAuthentication -TenantId $TenantId
if (-not $authSuccess) {
    Write-Error "Failed to authenticate to Azure"
    exit 1
}

# Validate all Azure resources exist
$resourcesValid = Test-AzureResources -VMConfigs $vmConfigs -MigrateProjectName $vmConfigs[0].MigrateProjectName -MigrateProjectResourceGroup $vmConfigs[0].MigrateProjectResourceGroup -MigrateProjectSubscriptionId $TargetSubscriptionId

if (-not $resourcesValid) {
    Write-Error "Resource validation failed. Please create missing resources and retry."
    exit 1
}

# Check replication infrastructure for each target subscription
Write-Header "Checking Replication Infrastructure"

$uniqueTargetSubscriptions = $vmConfigs.TargetSubscription | Select-Object -Unique
$infrastructureCheckSuccess = $true

foreach ($targetSubId in $uniqueTargetSubscriptions) {
    $resolvedTargetSubId = Get-SubscriptionId -SubscriptionIdentifier $targetSubId
    
    # Get subscription name for display
    $targetSub = Get-AzSubscription -SubscriptionId $resolvedTargetSubId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $targetSubName = if ($targetSub) { $targetSub.Name } else { $targetSubId }
    
    $infraCheckSuccess = Initialize-ReplicationInfrastructureForSubscription `
        -SubscriptionId $resolvedTargetSubId `
        -SubscriptionName $targetSubName `
        -MigrateProjectName $vmConfigs[0].MigrateProjectName `
        -MigrateProjectResourceGroup $vmConfigs[0].MigrateProjectResourceGroup `
        -TargetRegion $TargetRegion `
        -CheckOnly:$CheckOnly
    
    if (-not $infraCheckSuccess) {
        # Only fail if not in CheckOnly mode
        if (-not $CheckOnly) {
            $infrastructureCheckSuccess = $false
        }
    }
}

# If not in CheckOnly mode and infrastructure check failed, exit with error
if (-not $CheckOnly -and -not $infrastructureCheckSuccess) {
    Write-Error "Replication infrastructure initialization failed for one or more subscriptions. Cannot proceed."
    exit 1
}

# If check-only mode, exit here
if ($CheckOnly) {
    Write-Header "CHECK-ONLY Mode: Validation Complete"
    Write-Success "All validations and infrastructure checks passed. Ready to replicate."
    exit 0
}

# ============================================================================
# Start Replication
# ============================================================================

Write-Header "Starting Replication"

# Switch to migration project subscription once and retrieve all servers (this data is constant for all VMs)
try {
    $migrateProjectSubId = Get-SubscriptionId -SubscriptionIdentifier $TargetSubscriptionId
    Set-AzContext -SubscriptionId $migrateProjectSubId -WarningAction SilentlyContinue | Out-Null
    
    # Get the Migrate project and all discovered servers once
    $migrateProject = Get-AzMigrateProject -ResourceGroupName $vmConfigs[0].MigrateProjectResourceGroup -Name $vmConfigs[0].MigrateProjectName -ErrorAction Stop
    $allServers = Get-AzMigrateDiscoveredServer -ProjectName $vmConfigs[0].MigrateProjectName -ResourceGroupName $vmConfigs[0].MigrateProjectResourceGroup -ErrorAction Stop
    
    Write-Success "Retrieved $($allServers.Count) discovered servers from Azure Migrate project"
}
catch {
    Write-Error "Failed to retrieve Azure Migrate project or discovered servers: $_"
    exit 1
}

$replicationResults = @()

# Initialize caches for optimization
$subscriptionIdCache = @{}
$resourceCache = @{}  # keyed by "subscriptionId|resourceType|name|resourceGroup"

# Disk type mapping - create once, reuse for all VMs
$diskTypeMap = @{
    "Standard SSD"      = "StandardSSD_LRS"
    "StandardSSD_LRS"   = "StandardSSD_LRS"
    "Premium SSD"       = "Premium_LRS"
    "Premium_LRS"       = "Premium_LRS"
    "Standard"          = "Standard_LRS"
    "Standard_LRS"      = "Standard_LRS"
}

foreach ($vmConfig in $vmConfigs) {
    Write-Host "`n--- Processing: $($vmConfig.VMName) ---"
    
    # Check if replication is enabled for this VM
    if ($vmConfig.StartReplication -ne "Yes") {
        Write-Host "[!] Replication not enabled for $($vmConfig.VMName), skipping"
        $replicationResults += [PSCustomObject]@{
            VMName = $vmConfig.VMName
            Status = "SKIPPED"
            Reason = "StartReplication set to No"
        }
        continue
    }
    
    try {
        # Switch to target subscription for this VM's replication (use cache)
        if (-not $subscriptionIdCache.ContainsKey($vmConfig.TargetSubscription)) {
            $subscriptionIdCache[$vmConfig.TargetSubscription] = Get-SubscriptionId -SubscriptionIdentifier $vmConfig.TargetSubscription
        }
        $vmTargetSubId = $subscriptionIdCache[$vmConfig.TargetSubscription]
        Set-AzContext -SubscriptionId $vmTargetSubId -WarningAction SilentlyContinue | Out-Null
        
        # Find the discovered server for this VM from the pre-loaded list
        $discoveredServer = $allServers | Where-Object { $_.DisplayName -eq $vmConfig.VMName }
        
        if (-not $discoveredServer) {
            Write-Error "Discovered server not found: $($vmConfig.VMName)"
            $replicationResults += [PSCustomObject]@{
                VMName = $vmConfig.VMName
                Status = "FAILED"
                Reason = "Discovered server not found"
            }
            continue
        }
        
        # Check if replication already exists
        $existingReplication = Get-AzMigrateServerReplication -ProjectName $vmConfig.MigrateProjectName -ResourceGroupName $vmConfig.MigrateProjectResourceGroup -MachineName $vmConfig.VMName -ErrorAction SilentlyContinue
        
        if ($existingReplication) {
            Write-Warning "Replication already exists for $($vmConfig.VMName), skipping"
            $replicationResults += [PSCustomObject]@{
                VMName = $vmConfig.VMName
                Status = "SKIPPED"
                Reason = "Replication already exists"
            }
            continue
        }
        
        # Get target resources (use cache for VNet lookups)
        $vnetCacheKey = "$vmTargetSubId|VNet|$($vmConfig.TargetVirtualNetwork)|$($vmConfig.TargetVNetResourceGroup)"
        if (-not $resourceCache.ContainsKey($vnetCacheKey)) {
            $resourceCache[$vnetCacheKey] = Get-AzVirtualNetwork -Name $vmConfig.TargetVirtualNetwork -ResourceGroupName $vmConfig.TargetVNetResourceGroup -ErrorAction Stop
        }
        $targetVNet = $resourceCache[$vnetCacheKey]
        $targetSubnet = Get-AzVirtualNetworkSubnetConfig -Name $vmConfig.TargetSubnet -VirtualNetwork $targetVNet -ErrorAction Stop
        
        # Extract OS Disk ID from discovered server
        # The OSDiskID parameter expects the UUID of the disk
        if ($discoveredServer.Disk -and @($discoveredServer.Disk).Count -gt 0) {
            # Get the first disk's UUID
            $osDiskId = @($discoveredServer.Disk)[0].Uuid
            if ([string]::IsNullOrEmpty($osDiskId)) {
                # Fallback to disk label if UUID is empty
                $osDiskId = @($discoveredServer.Disk)[0].Label
            }
        } else {
            throw "No disks found on discovered server: $($vmConfig.VMName)"
        }
        
        if ([string]::IsNullOrEmpty($osDiskId)) {
            throw "Unable to extract OS disk ID from server $($vmConfig.VMName)"
        }
        
        # Get target resource group (use cache)
        $rgCacheKey = "$vmTargetSubId|RG|$($vmConfig.TargetResourceGroup)"
        if (-not $resourceCache.ContainsKey($rgCacheKey)) {
            $resourceCache[$rgCacheKey] = Get-AzResourceGroup -Name $vmConfig.TargetResourceGroup -ErrorAction Stop
        }
        $targetRG = $resourceCache[$rgCacheKey]
        
        # Use pre-loaded disk type mapping (created once before loop)
        $azureDiskType = if ($diskTypeMap.ContainsKey($vmConfig.DiskType)) {
            $diskTypeMap[$vmConfig.DiskType]
        } else {
            # Default to StandardSSD_LRS if unknown
            Write-Warning "Unknown disk type '$($vmConfig.DiskType)', using StandardSSD_LRS"
            "StandardSSD_LRS"
        }
        
        # Build replication parameters according to New-AzMigrateServerReplication documentation
        # Using the ByIdDefaultUser parameter set which requires: LicenseType, TargetResourceGroupId, TargetNetworkId, TargetSubnetName, TargetVMName, MachineId, DiskType, OSDiskID
        $replicationParams = @{
            MachineId                = $discoveredServer.Id
            TargetResourceGroupId    = $targetRG.ResourceId
            TargetNetworkId          = $targetVNet.Id
            TargetSubnetName         = $vmConfig.TargetSubnet
            TargetVMName             = $vmConfig.TargetVMName
            TargetVMSize             = $vmConfig.TargetVMSize
            OSDiskID                 = $osDiskId
            DiskType                 = $azureDiskType
            LicenseType              = if ($vmConfig.UseWindowsHybridBenefit -eq "Yes") { "WindowsServer" } elseif ($vmConfig.UseLinuxHybridBenefit -eq "Yes") { "RHEL_BYOS" } else { "NoLicenseType" }
            TargetAvailabilityZone   = if ([string]::IsNullOrEmpty($vmConfig.AvailabilityZone)) { "1" } else { $vmConfig.AvailabilityZone }
        }
        
        # Handle optional parameters
        if (-not [string]::IsNullOrEmpty($vmConfig.AvailabilitySetName)) {
            $availabilitySet = Get-AzAvailabilitySet -Name $vmConfig.AvailabilitySetName -ResourceGroupName $vmConfig.TargetResourceGroup -ErrorAction SilentlyContinue
            if ($availabilitySet) {
                $replicationParams["TargetAvailabilitySet"] = $availabilitySet.Id
            }
        }
        
        if (-not [string]::IsNullOrEmpty($vmConfig.Tags)) {
            try {
                $tagHashtable = $vmConfig.Tags | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
                if ($tagHashtable -and $tagHashtable.Count -gt 0) {
                    $replicationParams["Tag"] = $tagHashtable
                }
            } catch {
                # Silently skip tags if they cannot be parsed
            }
        }
        
        # Start replication
        Write-Host "Initiating replication for $($vmConfig.VMName)..."
        Write-Host "  - Machine ID: $($discoveredServer.Id)"
        Write-Host "  - Target VM Name: $($vmConfig.TargetVMName)"
        Write-Host "  - OS Disk ID: $osDiskId"
        
        $newReplication = New-AzMigrateServerReplication @replicationParams -WarningAction SilentlyContinue -ErrorAction Stop
        
        Write-Success "Replication started successfully for $($vmConfig.VMName)"
        
        $replicationResults += [PSCustomObject]@{
            VMName = $vmConfig.VMName
            Status = "SUCCESS"
            Reason = "Replication initiated"
            ReplicationId = $newReplication.Id
        }
    }
    catch {
        Write-Error "Failed to start replication for $($vmConfig.VMName): $_"
        
        $replicationResults += [PSCustomObject]@{
            VMName = $vmConfig.VMName
            Status = "FAILED"
            Reason = $_.Exception.Message
        }
    }
}

# ============================================================================
# Summary
# ============================================================================

Write-Header "Replication Summary"

$successful = $replicationResults | Where-Object { $_.Status -eq "SUCCESS" }
$failed = $replicationResults | Where-Object { $_.Status -eq "FAILED" }
$skipped = $replicationResults | Where-Object { $_.Status -eq "SKIPPED" }

Write-Host "`nSuccessful Replications: $($successful.Count)"
$successful | ForEach-Object { Write-Success "$($_.VMName)" }

Write-Host "`nSkipped: $($skipped.Count)"
$skipped | ForEach-Object { Write-Warning "$($_.VMName) - $($_.Reason)" }

Write-Host "`nFailed: $($failed.Count)"
$failed | ForEach-Object { Write-Error "$($_.VMName) - $($_.Reason)" }

# Export results
$reportPath = "$PSScriptRoot\ReplicationReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$replicationResults | Export-Csv -Path $reportPath -NoTypeInformation
Write-Success "Report saved to: $reportPath"

if ($failed.Count -gt 0) {
    exit 1
}
else {
    exit 0
}
