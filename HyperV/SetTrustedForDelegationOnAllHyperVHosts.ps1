$Domain = 'domain.local'
 
# Actually not needed anymore, but who knows...
Import-Module ActiveDirectory
# Put the NetBIOS names of your hosts here
$HyperVHosts = "HOST1","HOST2","HOST3","HOST4","HOST5"
 
ForEach($Host1 in $HyperVHosts)
{
    ForEach($Host2 in $HyperVHosts)
    {
        If($Host1 -ne $Host2)
        {
            "Delegating from $Host1 to $Host2..."
            Get-ADComputer $Host1 | Set-ADObject -Add @{"msDS-AllowedToDelegateTo" = "Microsoft Virtual System Migration Service/$($Host2).$($Domain)", "cifs/$($Host2).$($Domain)", "Microsoft Virtual System Migration Service/$Host2", "cifs/$Host2"}
            Get-ADComputer $Host1 | Set-ADAccountControl -TrustedForDelegation:$false -TrustedToAuthForDelegation:$true
        }
    }
}