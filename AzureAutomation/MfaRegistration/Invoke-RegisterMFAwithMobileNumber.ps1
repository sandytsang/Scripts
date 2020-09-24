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

#URL for query Group members 
$uri = "https://graph.microsoft.com/beta//groups/$GroupObjectId/members?`$select=userPrincipalName,mail,userType,mobilePhone"
$UsersRespond = Invoke-RestMethod -Method Get -Uri $uri -Headers $AuthTokenApp -ErrorAction SilentlyContinue
#Write-Output $UsersRespond.value

if($UsersRespond) {
    #Get the first page max 1000 user information
    $Users = $UsersRespond.value | Where-Object {$_.userType -ne 'Guest' -and $_.mobilePhone -ne $null}
    #Get MFA is not registered
    foreach ($User in $Users) {
        $userPrincipalName = $($user.userPrincipalName)
        $uri = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails?`$filter=userPrincipalName eq `'$userPrincipalName`' and isMfaRegistered eq false"
        $NoMFAUsersRespond = Invoke-RestMethod -Method Get -Uri $uri -Headers $AuthTokenApp
        if($NoMFAUsersRespond.value) {
            Write-Output "$userPrincipalName doesnot have MFA"
            $url = "https://graph.microsoft.com/beta/users/$userPrincipalName/authentication/phoneMethods"
            $ObjectBody = @{
                'phoneNumber' = "$($user.mobilePhone)"
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
        else {
            Write-Output "$($UserPrincipalName) has aleeady MFA"
        }
    }

    #Get Next Page users information
    $UsersNextLink = $UsersRespond."@odata.nextLink"
    while ($UsersNextLink -ne $null){
        $UsersRespond = (Invoke-RestMethod -Method Get -Uri $UsersNextLink -Headers $AuthTokenApp)
        $UsersNextLink = $UsersRespond."@odata.nextLink"
        $Users = $UsersRespond.value | Where-Object {$_.userType -ne 'Guest' -and $_.mobilePhone -ne $null}
        #Get MFA is not registered
        foreach ($User in $Users) {
            $userPrincipalName = $($user.userPrincipalName)
            $uri = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails?`$filter=userPrincipalName eq `'$userPrincipalName`' and isMfaRegistered eq false"
            $NoMFAUsersRespond = Invoke-RestMethod -Method Get -Uri $uri -Headers $AuthTokenApp
            if($NoMFAUsersRespond.value) {
                Write-Output "$userPrincipalName doesnot have MFA"
                $url = "https://graph.microsoft.com/beta/users/$userPrincipalName/authentication/phoneMethods"
                $ObjectBody = @{
                    'phoneNumber' = "$($user.mobilePhone)"
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
            else {
                Write-Output "$($UserPrincipalName) has aleeady MFA"
            }
        }
    }
}