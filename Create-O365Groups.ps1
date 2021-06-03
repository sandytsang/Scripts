#Connect to tenant Exchange Online
Connect-ExchangeOnline

#Get On-premises synced DL
$DistrubutionLists = Get-DistributionGroup | Where-Object {$_.IsDirSynced -eq $true}

#Get DL details
Foreach ($DistrubutionList in $DistrubutionLists) {
$GroupName = $DistrubutionList.Name


#Get DL members
$Members = Get-DistributionGroupMember -Identity $PrimarySmtpAddress

#Get DL owners
$Owners = $DistrubutionList.ManagedBy | Where-Object {$_ -ne "Organization Management"}

#Create New O365 Group
New-UnifiedGroup -DisplayName $GroupName

#Configure Group settings
Set-UnifiedGroup -Identity $GroupName -UnifiedGroupWelcomeMessageEnabled:$false -RequireSenderAuthenticationEnabled:$true -AccessType "Private" -AutoSubscribeNewMembers -SubscriptionEnabled:$true #-HiddenFromExchangeClientsEnabled -HiddenFromAddressListsEnabled:$true

#Accept only from some senders
if ($AcceptMessagesOnlyFrom) {

    Set-UnifiedGroup -Identity $GroupName -AcceptMessagesOnlyFrom $AcceptMessagesOnlyFrom
}
#Add members
$Members | foreach-object {Add-UnifiedGroupLinks -Identity $GroupName -LinkType "Members" -Links $_.Identity}

#Add owners
if($Owners) {
    $Owners | Get-User | foreach-object {Add-UnifiedGroupLinks -Identity $GroupName -LinkType "Owners" -Links "$_.UserPrincipalName"}
}
else {
#remove sandy admin from owner
    Add-UnifiedGroupLinks -Identity $GroupName -LinkType "Members" -Links "ga-cpin@dornangroup.onmicrosoft.com"
    Add-UnifiedGroupLinks -Identity $GroupName -LinkType "Owners" -Links "ga-cpin@dornangroup.onmicrosoft.com"
    Remove-UnifiedGroupLinks -Identity $GroupName -LinkType "Owners" -Links "adm-sze@dornangroup.com" -Confirm:$false
    Remove-UnifiedGroupLinks -Identity $GroupName -LinkType "Members" -Links "adm-sze@dornangroup.com" -Confirm:$false 
}

}

#Run the following after DL is deleted from domain, and run AAD sync

Foreach ($DistrubutionList in $DistrubutionLists) {
$GroupName = $DistrubutionList.Name
$PrimarySmtpAddress = $DistrubutionList.PrimarySmtpAddress
$OldAlias = $DistrubutionList.Alias


$NewGroup = Get-UnifiedGroup -Identity $GroupName
$NewAlias = $NewGroup.Alias
$Owners = $NewGroup.ManagedBy

Set-UnifiedGroup -Identity $GroupName -PrimarySmtpAddress "$PrimarySmtpAddress"
Set-UnifiedGroup -Identity $GroupName -EmailAddresses @{add="$OldAlias@dornangroup.com", "$OldAlias@dornangroup.onmicrosoft.com";Remove="$NewAlias@dornangroup.com", "$NewAlias@dornangroup.onmicrosoft.com"}
Set-UnifiedGroup -Identity $GroupName -Alias $OldAlias
}