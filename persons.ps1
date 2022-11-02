########################################################################
# HelloID-Conn-Prov-Source-Loket-Persons
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

        return $httpErrorObj
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


    # Get Employees
    $persons = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/$employerId/employees" -Headers $headers)
    Write-Verbose "Persons found [$($persons.Count)]"

    # Get Employments
    $responseEmployments = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/$employerId/employees/employments" -Headers $headers)
    Write-Verbose "Employments found [$($responseEmployments.Count)]"

    # Get Additional Employment Details
    foreach ($employment in $responseEmployments) {
        $function = Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/employees/employments/$($employment.id)/organizationalentities" -Headers $headers -verbose:$false
        $workinghours = Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/employees/employments/$($employment.id)/workinghours" -Headers $headers -verbose:$false

        $employment | Add-Member @{
            Function     = $function
            Workinghours = $workinghours
            ExternalId   = $employment.id
            DisplayName  = $employment.employee.employeeNumber
            Employer     = @{
                Name = $employer.companyName
                Code = $employer.employerNumber
                Id   = $employer.id
            }
        }
    }
    $contractsGrouped = $responseEmployments  | Group-Object DisplayName -AsHashTable -AsString

    Write-Verbose 'Importing raw data in HelloID'
    foreach ($person in $persons ) {
        $person | Add-Member -NotePropertyMembers @{
            ExternalId  = $person.Id
            DisplayName = $person.personalDetails.formattedName
            Contracts   = [System.Collections.Generic.List[object]]::new()
        }
        if ($null -ne $contractsGrouped["$($person.employeeNumber)"]) {
            $person.Contracts.AddRange($contractsGrouped["$($person.employeeNumber)"])
        }
        Write-Output $person | ConvertTo-Json -Depth 10
    }
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-LoketError -ErrorObject $ex
        Write-Verbose "Could not import Loket persons. Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Loket persons. Error: $($errorObj.FriendlyMessage)"
    } else {
        Write-Verbose "Could not import Loket persons. Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Loket persons. Error:  $($ex.Exception.Message)"
    }
}

