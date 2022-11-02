########################################################################
# HelloID-Conn-Prov-Source-Loket-Departments
#
# Version: 1.0.0
########################################################################
# Initialize default value's
$config = $Configuration | ConvertFrom-Json

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

#region functions
function Invoke-LoketRestMethod {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Uri,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary]
        $Headers,

        [Parameter()]
        [int]
        $PageSize = 250
    )
    $returnList = [System.Collections.Generic.List[object]]::new()
    $pageNumber = 0
    try {
        do {
            $pageNumber++
            $splatParams = @{
                Uri         = "$($Uri)?pageSize=$PageSize&pageNumber=$pageNumber"
                Method      = 'Get'
                ContentType = 'application/json'
                Headers     = $Headers
            }
            Write-Verbose "Invoking command '$($MyInvocation.MyCommand)' to endpoint '$($splatParams['Uri'])'"
            $rawResponse = Invoke-RestMethod @splatParams -Verbose:$false

            if ($rawResponse._embedded.count -gt 0) {
                $returnList.AddRange($rawResponse._embedded)
            }

        }until ( $rawResponse.totalPages -eq $rawResponse.currentPage  )
        Write-Output $returnList
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }

}

function Resolve-LoketError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = ''
            FriendlyMessage  = ''
        }

        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = "$($ErrorObject.Exception.Message) $($ErrorObject.ErrorDetails.Message)"
            try {
                $jsonErrorMessage = $ErrorObject.ErrorDetails.Message | ConvertFrom-Json
                $httpErrorObj.FriendlyMessage = switch ($jsonErrorMessage.Error) {
                    'Invalid_client' { "Failed to Authenticate, message [$($jsonErrorMessage.Error)]" }
                    'invalid_grant' { "Failed to Authenticate, message [$($jsonErrorMessage.Error)]" }
                    default { $ErrorObject.ErrorDetails.Message }
                }
            } catch {
                $httpErrorObj.FriendlyMessage = $ErrorObject.ErrorDetails.Message
            }
        } elseif ( $null -ne $ErrorObject.Exception.Response) {
            $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
            if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                $httpErrorObj.ErrorDetails = "$($ErrorObject.Exception.Message) $($streamReaderResponse)"
                try {
                    $jsonErrorMessage = $streamReaderResponse  | ConvertFrom-Json
                    $httpErrorObj.FriendlyMessage = switch ($jsonErrorMessage.Error) {
                        'Invalid_client' { "Failed to Authenticate, message [$($jsonErrorMessage.Error)]" }
                        'invalid_grant' { "Failed to Authenticate, message [$($jsonErrorMessage.Error)]" }
                        default { $jsonErrorMessage.Error }
                    }
                } catch {
                    $httpErrorObj.FriendlyMessage = $streamReaderResponse
                }
            } else {
                $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
                $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
            }
        } else {
            $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
            $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
        }

        Write-Output $httpErrorObj
    }
}
#endregion

try {
    switch ($config.Environment ) {
        'Acceptance' {
            $LoketApiUrl = 'https://api.loket-acc.nl'.trim('/')
            $AuthenticationServerUrl = 'https://oauth.loket-acc.nl/token'.trim('/')
            break
        }
        'Production' {
            $LoketApiUrl = 'https://api.loket.nl'.trim('/')
            $AuthenticationServerUrl = 'https://oauth.loket.nl/token'.trim('/')
            break
        }
        default {
            throw 'No valid environment provided. Valid Values are: [Acceptance, Production]'
        }
    }

    # Obtain Access Code with Refresh Token
    $tokenHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $tokenHeaders.Add('Content-Type', 'text/plain')
    $body = "grant_type=refresh_token&client_id=$($config.Client_Id)&client_secret=$($config.Client_Secret)&refresh_token=$($config.refresh_token)"
    $response = Invoke-RestMethod $AuthenticationServerUrl -Method 'POST' -Headers $tokenHeaders -Body $body -Verbose:$false

    # Set Authorisation Headers
    $headers = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $headers.Add('Content-Type', 'application/json')
    $headers.Add('Accept', 'application/json')
    $headers.Add('Authorization', "Bearer $($response.access_token)")

    # Get Required Employer GUID Based on name from the config
    $responseEmployer = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers" -Headers $headers)
    $employer = ($responseEmployer.Where( { $_.companyName -eq $config.employer }))
    $employerId = $employer.id

    if ([string]::IsNullOrEmpty(  $employerId )) {
        throw "Employer [$($config.employer)] not Found!"
    }

    # Get Departments
    $departments = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/$employerId/departments" -Headers $headers)
    Write-Verbose "departments found [$($departments.Count)]"

    # Get Departments users
    $userDepartments = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/$employerId/users/departments" -Headers $headers)
    Write-Verbose "departments users found [$($userDepartments.Count)]"
    $userDepartmentsGrouped = $userDepartments  | Group-Object userId -AsHashTable -AsString


    # Get users to acquire the mailadress required for correlation
    $users = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/$employerId/users" -Headers $headers)
    Write-Verbose "users found [$($users.Count)]"
    $departmentManagers = $users | Where-Object { $_.isDepartmentManager -eq $true } | Select-Object -Unique  *


    # Get Employees/ Persons to acquire the Employee / ManagerId
    $persons = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/$employerId/employees" -Headers $headers)
    Write-Verbose "Persons found [$($persons.Count)]"
    $personGrouped = $persons | Select-Object @{Name = 'Email'; Expression = { $_.contactInformation.emailAddress } }, * | Group-Object Email -AsHashTable -AsString


    # Create lookup List of manager - Departments
    $managerList = [System.Collections.Generic.list[object]]::new()
    foreach ($manager in  $departmentManagers ) {
        $manager | Add-Member -NotePropertyMembers @{
            userDepartments = $userDepartmentsGrouped["$($manager.id)"]
        }
        $managerEmployeeObject = $null
        $managerEmployeeObject = $personGrouped["$($manager.contactInformation.emailAddress)"]

        $departmentManagerOf = [array]($manager.userDepartments.departments)
        # Process each department for current Manager
        foreach ($deparmentMO in $departmentManagerOf) {
            if ($null -eq $managerEmployeeObject ) {
                Write-Warning "No EmployeeObject corelated for user [$($manager.userName)], No Departement Manger Set"
            } else {
                # Write-Verbose "EmployeeObject corelated for department. Manger set to [$($managerEmployeeObject.contactInformation.emailAddress)]"
            }

            $managerObject = @{
                ManagerUserId = $managerEmployeeObject.id
                ManagerEmail  = $managerEmployeeObject.contactInformation.emailAddress
                DepartmentId  = $deparmentMO.id
            }
            $managerList.Add( $managerObject)
        }
    }
    $uniqueManagerList = [array]($managerList | Select-Object -Unique)

    Write-Verbose 'Importing raw data in HelloID'
    foreach ($department in $departments ) {
        $department | Add-Member @{
            ExternalId        = $department.id
            DisplayName       = $department.description
            ManagerExternalId = ($uniqueManagerList | Where-Object { $_.DepartmentId -eq $department.id }).ManagerUserId
        }
        Write-Output $department | ConvertTo-Json -Depth 10
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-LoketError -ErrorObject $ex
        Write-Verbose "Could not import Loket departments. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Throw "Could not import Loket departments. Error: $($errorObj.FriendlyMessage)"
    } else {
        Write-Verbose "Could not import Loket departments. Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Throw "Could not import Loket departments. Error: $($errorObj.FriendlyMessage)"
    }
}

