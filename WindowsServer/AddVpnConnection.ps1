Add-VpnConnection -Name "enviaTel" -ServerAddress "pfSense2.zitzschennet.de" `
-TunnelType IKEv2 -AuthenticationMethod EAP -EncryptionLevel "Required"
Set-VpnConnectionIPsecConfiguration -ConnectionName "enviaTel" `
-AuthenticationTransformConstants SHA256128 -CipherTransformConstants AES256  `
-EncryptionMethod AES256 -IntegrityCheckMethod SHA256 -DHGroup Group14 -PfsGroup None -PassThru

route -p add 192.168.100.0 mask 255.255.255.0 192.168.200.253


route -p add 192.168.201.0 mask 255.255.255.0 192.168.200.253
route delete 192.168.200.0
route delete 192.168.100.0