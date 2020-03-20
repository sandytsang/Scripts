#This script is for fix Junos Pulse register NIC IP and VPN IP to internal dns server
#Requrired use GPO disable dns client dynamic update first
#
# Get connected interface.
$InterfaceAlias = (get-wmiobject win32_networkadapter | Where-Object {$_.netconnectionstatus -eq 2 -AND $_.ProductName -notlike 'Juniper Networks Virtual Adapter'}).NetConnectionID

#Reset interface dns to automatic
Get-NetConnectionProfile -InterfaceAlias $InterfaceAlias | Set-DnsClientServerAddress -ResetServerAddresses

#Reset interface connection suffix
Set-DnsClient -InterfaceAlias $InterfaceAlias -ConnectionSpecificSuffix "" -ResetConnectionSpecificSuffix

#Allow Dynamic update dns
New-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -PropertyType DWORD -Name 'RegistrationEnabled' -Value 1 -Force

#Register client ip back to dns server
Register-DnsClient -Verbose

#Disable dynamic update again.
New-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -PropertyType DWORD -Name 'RegistrationEnabled' -Value 0 -Force
