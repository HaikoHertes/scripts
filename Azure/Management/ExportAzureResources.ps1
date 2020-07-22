<#
    .DESCRIPTION
        This Script exports all Azure Resources within a given Tenant into JSON-based ARM templates and uploads them as a ZIP file to an Azure Storage Account.
        Pay attention that this script creates files and folders forcefully, so existing files/folders might be overwritten if existing.
        The script requires Az PowerShell modules Az.Accounts, Az.Automation, Az.Resources and Az.Storage to be installed.
    .NOTES
        AUTHOR: Haiko Hertes
                Microsoft MVP & Azure Architect
                SoftwareONE Deutschland GmbH
        LASTEDIT: 2020/07/08
#>

$ExportSingleResources = $false         # Set this to $true if you want to export single resources in addition to whole RGs - can become very time-consuming!
$CleanUpOldFiles = $true                # Do you want the script to delete old files on Azure Storage Account?
$DaysToKeep = 60                        # The amount of days an exported file will be kept on Azure Storage Account

$SendResultsViaMail = $true               # Set this to $true if you want to get an email on completion, otherwise set it to $false
$SmtpServer = "SERVER.DOMAIN.COM"         # SMTP Mail Server Adress, needs to use TCP/25
$SmtpRecipient = "receiver@domain.com"    # Recipient adress for the email
$SmtpSender = "sender@domain.com"         # Sender adress for the email
                                        
$runbookName = "PUT-RUNBOOKNAME-HERE"  # The name of the runbook where this Script is run from - needed to prevent the runbook from running twice at the same time
$rgName = "PUT-RESOURCEGROUP-NAME-HERE"                     # The Resource Group where the Azure Autmation Account is deployed to
$aaName = "PUT-AZURE-AUTOMATION-ACCOUNT-HERE"                      # The Resource name of the Azure Automation Account

$AuthenticateWithSecret = $false                   # When set to $true, ServicePrincipalId and ClientSecret will be used for autnentication; Otherwiese Certificates will be used
$connectionName = "AzureRunAsConnection"           # Name of the RunAs connection used by the Automation Account

# When using ClientSecret (AuthenticateWithSecret is set to true), these values need to be provided
$tenantId = "PUT-TENANT-ID-HERE"             # Azure AD / Tenant Id
$servicePrincipalId = "PUT-SERVICE-PRINCIPAL-ID-HERE"   # Object / Service Principal ID
$ClientSecret = "PUT-CLIENT-SECRET-HERE"           # Client Secret for Service Principal - only needed when $AuthenticateWithSecret is set to true

# these are for the storage account to be used
$storageAccountSubscription = "PUT-SUBSCRIPTION-NAME-HERE"
$storageAccountResourceGroup = "PUT-RESOURCEGROUP-NAME-HERE"
$storageAccountName = "PUT-STORAGEACCOUNT-NAME-HERE"
$containerName = "PUT-CONTAINER-NAME-HERE"

<####################################################>
<######                                         #####>
<######  NO NEED TO CHANGE ANYTHING BELOW HERE  #####>
<######                                         #####>
<####################################################>

# Ensures that you do not inherit an AzContext in your runbook
Disable-AzContextAutosave –Scope Process
# To deal with multiple subscriptions, your runbook must use the Disable-AzContextAutosave cmdlet. This cmdlet ensures that the authentication context isn't retrieved from another runbook running in the same sandbox. The runbook also uses theAzContext parameter on the Az module cmdlets and passes it the proper context.

# Login to Azure with AzureRunAsConnection
try
{
    If($AuthenticateWithSecret)
    {
        "Logging into Azure using service principal and client secret"
        $pscredential = New-Object -TypeName System.Management.Automation.PSCredential($servicePrincipalId, $(ConvertTo-SecureString $ClientSecret -AsPlainText -Force))
        Connect-AzAccount -ServicePrincipal -Credential $pscredential -Tenant $tenantId
    }
    else
    {
        "Logging into Azure using service principal and certificate"
        # Get the connection "AzureRunAsConnection "
        $ServicePrincipalConnection = Get-AutomationConnection -Name $connectionName
        Connect-AzAccount `
            -ServicePrincipal  `
            -Tenant $ServicePrincipalConnection.TenantID `
            -ApplicationId $ServicePrincipalConnection.ApplicationID `
            -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint
    }
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Check for already running or new runbooks
$jobs = Get-AzAutomationJob -ResourceGroupName $rgName -AutomationAccountName $aaName -RunbookName $runbookName -AzContext $AzureContext

# Check to see if it is already running
$runningCount = ($jobs | ? {$_.Status -eq "Running"}).count

If (($jobs.status -contains "Running" -And $runningCount -gt 1 ) -Or ($jobs.Status -eq "New")) {
    # Exit code
    "Runbook is already running - aborting!"
    Exit 1
} else {
    
    $InitialDirectory = (Get-Location).Path
    $fileCount = 0
    "Starting the export..."

    Set-Location -Path $InitialDirectory

    ForEach($Subscription in (Get-AzSubscription))
    {
        $SubFolder = New-Item -Path (Join-Path -Path $InitialDirectory -ChildPath ($Subscription.Name)) -Type Directory -Force
        Set-Location $SubFolder
        
        "Switching to Subscription $Subscription"
        Set-AzContext -SubscriptionId $Subscription.ID
                
        ForEach($RG in (Get-AzResourceGroup))
        {
            
            $RGFolder = New-Item -Path (Join-Path -Path $SubFolder -ChildPath ($RG.ResourceGroupName)) -Type Directory -Force
            Set-Location $RGFolder

            # Export all resources in RG all together
            Export-AzResourceGroup -ResourceGroupName $($RG.ResourceGroupName) -WarningAction SilentlyContinue -Force
            $fileCount++

            If($ExportSingleResources)
            {
                # Export all resources in single files
                ForEach($Resource in (Get-AzResource -ResourceGroupName $($RG.ResourceGroupName)))
                {
                    Export-AzResourceGroup -ResourceGroupName $($RG.ResourceGroupName) -Resource $Resource.Id -Path "$((Get-Location).Path)\SingleResources\$($Resource.Name.Replace("/","_"))"  -WarningAction SilentlyContinue -Force
                    $fileCount++
                }
            }
        }
    }
    Set-Location -Path $InitialDirectory

    $FileName = "$(Get-Date -Format yyyyMMdd)-AllTemplates.zip"

    "Compressing the $fileCount templates into a single Zip file..."
    Compress-Archive -Path "$InitialDirectory\*" -DestinationPath (Join-Path -Path $InitialDirectory -ChildPath $FileName) -Force 

    Set-AzContext -SubscriptionId (Get-AzSubscription -SubscriptionName $storageAccountSubscription).ID

    # get a reference to the storage account and the context
    $storageAccount = Get-AzStorageAccount `
        -ResourceGroupName $storageAccountResourceGroup `
        -Name $storageAccountName
    $context = $storageAccount.Context 

    "Uploading the zipped templates to the Storage Account..."
    $blob = Set-AzStorageBlobContent `
        -File $FileName `
        -Container $containerName `
        -Blob $FileName `
        -BlobType Block `
        -Context $context `
        -Force

    If($CleanUpOldFiles)
    {
        # Cleaning up files older than X days
        "Cleaning up files older than $DaysToKeep days..."
        Get-AzStorageBlob -Container $containerName -Context $context | Where {$_.LastModified -lt (Get-Date).AddDays(-$DaysToKeep)} | Remove-AzStorageBlob
    }

    If($SendResultsViaMail)
    {
        $body = "<h1>Azure Resource Export Script done!</h1>" 
        $body += "Azure Automation has finished the export of all Azure resources to a Storage Account.<br>$fileCount files were generated.<br><br>" 
        $body += "The exported templates can be downloaded as a zip file from here: <a href='$($blob.ICloudBlob.uri.AbsoluteUri)'>$($blob.ICloudBlob.uri.AbsoluteUri)</a>"
        Send-MailMessage -SmtpServer $SmtpServer -Attachments $FileName -Subject "Azure Template Export done - $fileCount files were exported and uploaded" -Body $body -BodyAsHtml -To $SmtpRecipient -From $SmtpSender 
    }

    "Script is done - $fileCount single templates exported and zipped - overall file is available from here: $($blob.ICloudBlob.uri.AbsoluteUri)"
}