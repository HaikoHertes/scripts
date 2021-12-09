$AllAzureDNSZones = 'azure-automation.net',
                    'database.windows.net',
                    'sql.azuresynapse.net',
                    'sqlondemand.azuresynapse.net',
                    'dev.azuresynapse.net',
                    'azuresynapse.net',
                    'blob.core.windows.net',
                    'table.core.windows.net',
                    'queue.core.windows.net',
                    'file.core.windows.net',
                    'web.core.windows.net',
                    'dfs.core.windows.net',
                    'documents.azure.com',
                    'mongo.cosmos.azure.com',
                    'cassandra.cosmos.azure.com',
                    'gremlin.cosmos.azure.com',
                    'table.cosmos.azure.com',
                    '{region}.batch.azure.com',
                    'postgres.database.azure.com',
                    'mysql.database.azure.com',
                    'mariadb.database.azure.com',
                    'vault.azure.net',
                    'vaultcore.azure.net',
                    '{region}.azmk8s.io',
                    'search.windows.net',
                    'azurecr.io',
                    'azconfig.io',
                    '{region}.backup.windowsazure.com',
                    '{region}.hypervrecoverymanager.windowsazure.com',
                    'servicebus.windows.net',
                    'servicebus.windows.net',
                    'azure-devices.net',
                    'servicebus.windows.net',
                    'servicebus.windows.net',
                    'eventgrid.azure.net',
                    'eventgrid.azure.net',
                    'azurewebsites.net',
                    'api.azureml.ms',
                    'notebooks.azure.net',
                    'instances.azureml.ms',
                    'aznbcontent.net',
                    'service.signalr.net',
                    'monitor.azure.com',
                    'oms.opinsights.azure.com',
                    'ods.opinsights.azure.com',
                    'agentsvc.azure-automation.net',
                    'blob.core.windows.net',
                    'cognitiveservices.azure.com',
                    'afs.azure.net',
                    'datafactory.azure.net',
                    'adf.azure.com',
                    'redis.cache.windows.net',
                    'redisenterprise.cache.azure.net',
                    'purview.azure.com',
                    'purview.azure.com',
                    'digitaltwins.azure.net',
                    'azurehdinsight.net'

$CheckedByDefault = 'database.windows.net',
                    'blob.core.windows.net',
                    'table.core.windows.net',
                    'queue.core.windows.net',
                    'file.core.windows.net',
                    'vault.azure.net',
                    'vaultcore.azure.net',
                    'azurewebsites.net'

function ShowCheckedListBox{
    param(
        $AllEntries,
        $CheckedEntries
    )

    # Import Windows Forms Assembly
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    # Create a Form
    $Form = New-Object -TypeName System.Windows.Forms.Form
    $form.Text = 'Select Azure Services / DNS Zones to use'
    $form.Size = New-Object System.Drawing.Size(340,500)
    $form.StartPosition = 'CenterScreen'
    # Create a CheckedListBox
    $CheckedListBox = New-Object -TypeName System.Windows.Forms.CheckedListBox;
    $CheckedListBox.Location = New-Object System.Drawing.Point(10,10)
    # Add the CheckedListBox to the Form

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Location = New-Object System.Drawing.Point(120,420)
    $okButton.Size = New-Object System.Drawing.Size(80,25)
    $okButton.Text = 'OK'
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton = $okButton
    
    $Form.Controls.Add($CheckedListBox)
    $form.Controls.Add($okButton)
    # Widen the CheckedListBox
    $CheckedListBox.Width = 300;
    $CheckedListBox.Height = 400;
    # Add 10 items to the CheckedListBox
    $CheckedListBox.Items.AddRange(@($AllEntries))

    # Clear all existing selections
    $CheckedListBox.ClearSelected();
    # Define a list of items we want to be checked


    # For each item that we want to be checked ...
    foreach ($Item in $CheckedEntries) {
        # Check it ...
        $CheckedListBox.SetItemChecked($CheckedListBox.Items.IndexOf($Item), $true);
    }

    

    # Show the form
    $Form.ShowDialog();
    Return $CheckedListBox.CheckedItems


}

$DNSServersList = @()
Do{
    $DNSServer = Read-Host "Enter the IP Adress of your Azure-based DNS Server that acts as DNS forwarder. Press ENTER to stop adding servers."
    If($DNSServer -ne ""){
        $DNSServersList += $DNSServer
    }
}Until($DNSServer -eq "")


$RegionList = @()
Do{
    $Region = Read-Host "Enter the Azure Regions that need to be used for region-specific DNS Zones. Press ENTER to stop adding Regions."
    If($Region -ne ""){
        $RegionList += $Region
    }
}Until($Region -eq "")

Write-Host "Select Azure Services / DNS Zones to use from the CheckedListBox..."
$DNSZonesToUse = ShowCheckedListBox -AllEntries $AllAzureDNSZones -CheckedEntries $CheckedByDefault

Write-Host "Creating list of PowerShell statements..."
$PSStatements = @()
ForEach($DNSZone in ($DNSZonesToUse |Where-Object {($_ -ne "Cancel") -and ($_ -ne "OK")}))
{
    If($DNSZone -like "{region}*")
    {
        ForEach($Region in $RegionLIst)
        {
            $DNSZoneName = $DNSZone.Replace("{region}",$Region)
            $PSStatements += "Add-DnsServerConditionalForwarderZone -Name ""$DNSZoneName"" -MasterServers $($DNSServersList -join ",")"
        }
    }
    else {
        $PSStatements += "Add-DnsServerConditionalForwarderZone -Name ""$DNSZone"" -MasterServers $($DNSServersList -join ",")"
    }
}
Write-Host "Creating list of PowerShell statements done!"
$PSStatements | Out-File "SetConditionalForwardingForAzurePrivateEndpoint.ps1"
Write-Host "SetConditionalForwardingForAzurePrivateEndpoint.ps1 was saved to current directory. Run it on all on-premises DNS Servers!"