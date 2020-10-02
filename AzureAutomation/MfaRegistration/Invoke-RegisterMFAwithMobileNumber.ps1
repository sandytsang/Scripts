<#
.SYNOPSIS
    This script is for get no MFA registered users, use in Azure Automation Account

.DESCRIPTION
    This script will get no MFA registered users

.NOTES
    File name: Invoke-CheckMfaRegistration.ps1
    VERSION: 1.1.0
    AUTHOR: Sandy Zeng
    Created:  2020-09-23
    COPYRIGHT:
    Sandy Zeng / https://www.sandyzeng.com
    Licensed under the MIT license.
    Please credit me if you fint this script useful and do some cool things with it.


.VERSION HISTORY:
    1.0.0 - (2020-09-23) Script created
    1.1.0 - (2020-10-01) Added throttling handling
    1.1.1 - (2020-10-01) Credit from Jan Ketil Skanke, make better throttling and paging https://github.com/MSEndpointMgr/AzureAD/blob/master/MSGraph-HandlePagingandThrottling.ps1
    1.1.2 - (2020-10-02) Removed exit 1, so that script will continue runs even there is error
#>

Import-Module -Name MSAL.PS

$scope = "https://graph.microsoft.com/.default"
$Tenant = "mvp24.onmicrosoft.com" #List here your tenants
$authority = "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token"
$AppID = Get-AutomationVariable -Name "AppID" #Change this to your own Azure Automation app ID
$AppSecret = Get-AutomationVariable -Name "AppSecret" #Change this to your own Azure Automation App Secret
$AuthenticationCredentials = Get-AutomationPSCredential -Name "something@mvp24.onmicrosoft.com" #Change this to your own Azure Automation credential
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

#Get all no MFA registered users
$NoMFAUsers = @()
$url = "https://graph.microsoft.com/beta/reports/credentialUserRegistrationDetails?`$filter=isMfaRegistered eq false"

do {
    $RetryIn = "0"
    $ThrottledRun = $false
    Write-Output "Querying $url"
    try {
        $NoMFAUsersRespond = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthTokenApp
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $MyError = $_.Exception
        if (($MyError.Response.StatusCode) -eq "429") {
            $ThrottledRun = $true
            $RetryIn = $MyError.Response.Headers["Retry-After"]
            Write-Warning -Message "Graph queries is being throttled by Microsoft"
            Write-Output "Settings throttle retry to $($RetryIn)"
        } 
        else {
            Write-Error -Message "Inital graph query failed with $ErrorMessage"
        }
    }

    if ($ThrottledRun -eq $false) {
        #If request is not throttled put data into result object
        $NoMFAUsers += $NoMFAUsersRespond.value

        #If request is not trottled, go to nextlink if available to fetch more data
        $url = $NoMFAUsersRespond.'@odata.nextlink'
    }

    Start-Sleep -Seconds $RetryIn
} 
Until (!($url))


#All No MFA users principalName
$NoMFAUsersUPN = $NoMFAUsers.userPrincipalName

#Get members from Azure AD group
$GroupMembers = @()
$url = "https://graph.microsoft.com/beta//groups/$GroupObjectId/members?`$select=userPrincipalName,mail,userType,mobilePhone"
do {
    $RetryIn = "0"
    $ThrottledRun = $false
    Write-Output "Querying $url"    
    try {
        $UsersRespond = Invoke-RestMethod -Method Get -Uri $url -Headers $AuthTokenApp -ErrorAction SilentlyContinue
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        $MyError = $_.Exception
        if (($MyError.Response.StatusCode) -eq "429") {
            $ThrottledRun = $true
            $RetryIn = $MyError.Response.Headers["Retry-After"]
            Write-Warning -Message "Graph queries is being throttled by Microsoft"
            Write-Output "Settings throttle retry to $($RetryIn)"
        } 
        else {
            Write-Error -Message "Inital graph query failed with $ErrorMessage"
        }
    }

    if ($ThrottledRun -eq $false) {
        #If request is not throttled put data into result object      
        $GroupMembers += $UsersRespond.value | Where-Object {$_.userType -ne 'Guest' -and $_.mobilePhone -ne $null}
        
        #If request is not trottled, go to nextlink if available to fetch more data
        $url = $NoMFAUsersRespond.'@odata.nextlink'        
    }

    $url = $UsersRespond.'@odata.nextlink'
    Start-Sleep -Seconds $RetryIn

} 
Until (!($url))

#All Group Member user PrindipalName
$GroupMemberUPN = $GroupMembers.userPrincipalName

#Compare results and get no MFA register user that are belong to the Azure AD group
$UserObjects = (Compare-Object -ReferenceObject $NoMFAUsersUPN -DifferenceObject $GroupMemberUPN -Includeequal -ExcludeDifferent).InputObject

#Provision users mobile phone number as authentication phone method
foreach ($UserObject in $UserObjects) {
    Write-Output "====================================================================="      
    Write-Output "$UserObject does not have MFA, start provisiong phone methods for MFA"  
    $UserMobilePhone = ($GroupMembers | Where-Object {$_.userPrincipalName -match "$UserObject"}).mobilePhone
    $url = "https://graph.microsoft.com/beta/users/$UserObject/authentication/phoneMethods"
    $ObjectBody = @{
        'phoneNumber' = "$($UserMobilePhone)"
        'phoneType' = "mobile"
    }
    $json = ConvertTo-Json -InputObject $ObjectBody
    do {
        $RetryIn = "0"
        $ThrottledRun = $false
        Write-Output "Querying $url"          
        try {  
            Invoke-RestMethod -Method POST -Uri $url -Headers $AuthTokenUser -Body $json
            Write-Output "$UserObject MFA methods is configured wiht phone number $UserMobilePhone"  
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $MyError = $_.Exception
            if (($MyError.Response.StatusCode) -eq "429") {
                $ThrottledRun = $true
                $RetryIn = $MyError.Response.Headers["Retry-After"]
                Write-Warning -Message "Graph queries is being throttled by Microsoft"
                Write-Output "Settings throttle retry to $($RetryIn)"
            } 
            else {
                Write-Error -Message "Inital graph query failed with $ErrorMessage"
            }
        }

        Start-Sleep -Seconds $RetryIn
    }
    while (ThrottledRun -eq $true)
}