Add-DnsServerConditionalForwarderZone -Name "database.windows.net" -MasterServers 
Add-DnsServerConditionalForwarderZone -Name "blob.core.windows.net" -MasterServers 
Add-DnsServerConditionalForwarderZone -Name "table.core.windows.net" -MasterServers 
Add-DnsServerConditionalForwarderZone -Name "queue.core.windows.net" -MasterServers 
Add-DnsServerConditionalForwarderZone -Name "file.core.windows.net" -MasterServers 
Add-DnsServerConditionalForwarderZone -Name "vault.azure.net" -MasterServers 
Add-DnsServerConditionalForwarderZone -Name "vaultcore.azure.net" -MasterServers 
Add-DnsServerConditionalForwarderZone -Name "azurewebsites.net" -MasterServers 
