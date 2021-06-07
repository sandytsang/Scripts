#Create Office 365 Groups
param(
    [Parameter(Mandatory)]
    [string]$GroupName
)

Connect-ExchangeOnline

#Get Group
$check = Get-UnifiedGroup -Identity $GroupName -ErrorAction SilentlyContinue

If (!$check) {
    Write-Host "Creating $GroupName"

    try {
        #Create New O365 Group
        New-UnifiedGroup -DisplayName $GroupName
        Start-Sleep 3

        #Configure Group settings
        Write-Host "Configuring group settings"
        Set-UnifiedGroup -Identity $GroupName -UnifiedGroupWelcomeMessageEnabled:$false -RequireSenderAuthenticationEnabled:$true -AccessType "Private" -AutoSubscribeNewMembers -SubscriptionEnabled:$true -Verbose -ErrorAction Stop
    }
    catch {
        Write-Warning $Error[0]
    }
}
else {
    Write-Host "Group name : $GroupName is already existed" -ForegroundColor Red
}
