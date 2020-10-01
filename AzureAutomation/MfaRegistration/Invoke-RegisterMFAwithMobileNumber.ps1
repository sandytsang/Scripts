Import-Module -Name MSAL.PS

$scope = "https://graph.microsoft.com/.default"
$Tenant = "mvp24.onmicrosoft.com" #List here your tenants
$authority = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"
$AppID = Get-AutomationVariable -Name "AppID" #Change this to your own app ID
$AppSecret = Get-AutomationVariable -Name "AppSecret" #Change this to your own App Secret
$AuthenticationCredentials = Get-AutomationPSCredential -Name "something@mvp24.onmicrosoft.com"
$GroupObjectId = "457323e2-713c-4766-b47c-987017c48160"


###Get Access Token for Application permission
$authHeader = @{
    'Content-Type' = 'application/x-www-form-urlencoded'
}

$authBody = @{
    'client_id'        = $AppId
    'grant_type'    = "client_credentials"
    'client_secret' = "$AppSecret"
    'scope'            = $scope
}

try {
    $RequestApp = Invoke-RestMethod -Headers $authHeader -Uri $authority -Body $authBody -Method POST
    $AuthTokenApp = @{
        Authorization = "Bearer $($RequestApp.access_token)"
    }
}
catch {
    Write-Warning "$Error[0]"
}

###Get Access Token for delegated permission
$requestUser = Get-MsalToken -ClientId $AppID -TenantId $Tenant -UserCredential $AuthenticationCredentials -RedirectUri "https://login.microsoftonline.com/common/oauth2/nativeclient" -Verbose
$access_token = $requestUser.CreateAuthorizationHeader()
$AuthTokenUser = @{
    Authorization = "$access_token"
}

##Get all no MFA registered users
$NoMFAUsers = @()
do {
    try {
        $url = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails?`$filter=isMfaRegistered eq false"
        $NoMFAUsersRespond = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthTokenApp
        $NoMFAUsers = $NoMFAUsersRespond.value
        $StatusCode = $NoMFAUsersRespond.StatusCode
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        if ($StatusCode -eq 429) {
            Write-Warning "Got throttled by Microsoft. Sleeping for 45 seconds..."
            Start-Sleep -Seconds 10
        }
        else {
            Write-Error $_.Exception
        }
    }
} 
while ($StatusCode -eq 429)

#Get Next page users
do {
    try {
        $NoMFAUsersNextLink = $NoMFAUsersRespond."@odata.nextLink"
        while ($NoMFAUsersNextLink -ne $null){
            $NoMFAUsersRespond = (Invoke-RestMethod -Method Get -Uri $NoMFAUsersNextLink -Headers $AuthTokenApp)
            $StatusCode = $NoMFAUsersRespond.StatusCode
            $NoMFAUsersNextLink = $NoMFAUsersRespond."@odata.nextLink"
            $NoMFAUsers += $NoMFAUsersRespond.value
        }
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        if ($StatusCode -eq 429) {
            Write-Warning "Got throttled by Microsoft. Sleeping for 45 seconds..."
            Start-Sleep -Seconds 10
        }
        else {
            Write-Error $_.Exception
        }
    }
} 
while ($StatusCode -eq 429)

#All No MFA users principalName
$NoMFAUsersUPN = $NoMFAUsers.userPrincipalName

##Get members from Azure AD group
$Users = @()
do {
    try {
        $url = "https://graph.microsoft.com/beta//groups/$GroupObjectId/members?`$select=userPrincipalName,mail,userType,mobilePhone"
        $UsersRespond = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthTokenApp -ErrorAction SilentlyContinue
        $StatusCode = $UsersRespond.StatusCode

        #Filter out guest users and no mobile phone number users
        $Users = $UsersRespond.value | Where-Object {$_.userType -ne 'Guest' -and $_.mobilePhone -ne $null}
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        if ($StatusCode -eq 429) {
            Write-Warning "Got throttled by Microsoft. Sleeping for 45 seconds..."
            Start-Sleep -Seconds 10
        }
        else {
            Write-Error $_.Exception
        }
    }
} 
while ($StatusCode -eq 429)

#Get Next Page users
do {
    try {        
        $UsersNextLink = $UsersRespond."@odata.nextLink"
        while ($UsersNextLink -ne $null){
            $UsersRespond = (Invoke-RestMethod -Method Get -Uri $UsersNextLink -Headers $AuthTokenApp)
            $StatusCode = $UsersRespond.StatusCode
            $UsersNextLink = $UsersRespond."@odata.nextLink"
            $Users += $UsersRespond.value | Where-Object {$_.userType -ne 'Guest' -and $_.mobilePhone -ne $null}
        }
    }
    catch {
        $StatusCode = $_.Exception.Response.StatusCode.value__
        if ($StatusCode -eq 429) {
            Write-Warning "Got throttled by Microsoft. Sleeping for 45 seconds..."
            Start-Sleep -Seconds 10
        }
        else {
            Write-Error $_.Exception
        }
    }
} 
while ($StatusCode -eq 429)

#All Group Member user PrindipalName
$GroupMemberUPN = $Users.userPrincipalName

#Compare results and get no MFA register user that are belong to the Azure AD group
$UserObject = (Compare-Object -ReferenceObject $NoMFAUsersUPN -DifferenceObject $GroupMemberUPN -Includeequal -ExcludeDifferent).InputObject
Write-Output "$UserObject does not have MFA"        

#Provision users mobile phone number as authentication phone method
foreach ($UserObject in $UserObjects) {
    $UserMobilePhone = ($Users | Where-Object {$_.userPrincipalName -match "$UserObject"}).mobilePhone
    $url = "https://graph.microsoft.com/beta/users/$UserObject/authentication/phoneMethods"
    $ObjectBody = @{
        'phoneNumber' = "$($UserMobilePhone)"
        'phoneType' = "mobile"
    }
    $json = ConvertTo-Json -InputObject $ObjectBody
    try {
        Invoke-RestMethod -Method POST -Uri $url -Headers $AuthTokenUser -Body $json -Verbose
    }
    catch {
        Write-Warning "$Error[0]"
    }
}