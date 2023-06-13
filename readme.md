
# HelloID-Conn-Prov-Source-Loket

| :information_source: Information |
|:---------------------------|
| This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements. |
<br />
<p align="center">
  <img src="https://www.tools4ever.nl/connector-logos/loket-logo.png" width="500">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Source-Loket_ is a _source_ connector. Loket provides a set of REST API's that allow you to programmatically interact with its data.

> **Warning:** The department managers in Loket are user accounts without a link to an employee. The current code base correlates users and employees based on Email address.


## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| Client_Id           | The Client_Id to connect to the API | Yes         |
| Client_Secret       | The Client_Secret to connect to the API | *Whether client_secret is required is dependent on the configuration of the client*        |
| refresh_token       | The refresh_token to connect to the API. The refresh token can be obtained in a different [Process](https://developer.loket.nl/OauthCode).                | Yes         |
| Environment         | Acceptation or Production (Default URL's)       | Yes         |
| Employer            | The Name of the employer in Loket           | Yes         |
| Loket User          |A Loket user account with access to the Employer. *Required to get the Refresh Token.*  | Yes         |



### Prerequisites
- Determine a manager calculation *(See Remarks)*
- Get manually a refresh token. The Refresh token is required to get unattended an access token. Please check the paragraph 'Acquire Refresh Token' below, or use the information provided directly by Loket. [Loket Instructions](https://developer.loket.nl/OauthCode)


### Remarks
- There is no manager field on an Employee by default in Loket.
  When required the Supplier suggested two following possibilities, both needs some custom scripting (and configuration in the connector)
    - **FreeField**
      The manager can be added in a custom field in Loket. This endpoint is **Not** default added in the code. The manager value should also be added to the person or contract model.
      ```Powershell
        # Example Code to retrieve custom fields, might be used for the manager
        # $customFields = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/employees/$($person.id)/customfields" -Headers $headers -verbose:$false)

      ```

    - **Correlation based on Business Mail** *(Currently implemented in the code)*
    The department managers in Loket are user accounts without a link to an employee. The current code base correlates users and employees based on Email address. The email address is present on both objects. (Please keep this in mind that this is not 100% reliable.)
    ``` Powershell
      # Get Employees/ Persons to acquire the Employee / ManagerId
      $persons = [array](Invoke-LoketRestMethod -Uri "$($LoketApiUrl)/v2/providers/employers/$employerId/employees" -Headers $headers)
      Write-Verbose "Persons found [$($persons.Count)]"
      $personGrouped = $persons | Select-Object @{Name = 'Email'; Expression = { $_.contactInformation.emailAddress } }, * | Group-Object Email -AsHashTable -AsString

      ## Foreach Manager
        $managerEmployeeObject = $personGrouped["$($manager.contactInformation.emailAddress)"]

    ```

- The Cost Bearer/CostCenter property depends on how the Loket is configured. By default the CostCenter is retrieved based on an employment property (Currently this is implemented in the code and Mapping.) When the Customer uses JournalProfile 'journaalprofiel' the cost-center can be retrieved from a different endpoint: *GetJournalAllocationsByEmploymentId --> CostCenter en CostUnit.* This is not implemented by default but can be added with additional scripting.


## Acquire Refresh Token
Supplier documentation can be found here: https://developer.loket.nl/OauthCode

##### 1. Fill in the parameters of your tenant

```Powershell
  #  Have the Loket user available with access to the required Loket employer.
  $clientID = 'xxxx'
  $clientSecret = 'xxxx'                      #  When used change the Body in Step 4
  $redirect_uri = 'https://loket.nl'          #
  $baseurl = 'https://oauth.loket-acc.nl'     #  https://oauth.loket-acc.nl   // https://oauth.loket.nl
```

##### 2. Generate URL and paste the URL into the Browser
```Powershell
#     A log in screen appears.
#     User is prompted to login using Loket-credentials (username + password)
#     If enabled the user must supply a valid TOTP (Time-based One-time Password).
#
#       After a successfull login, copy the code from the address bar
#       Url structure: {redirect_uri}?state={state}&code={code}
#       Example: https://loket.nl/return?state=UniqueId&code=23094z5u2j35h3985uk2j35p092358j4362398u462po4

$url = "$baseurl/authorize?client_id=$clientID&redirect_uri=$redirect_uri&response_type=code&scope=all&state=1234"
$url | Set-Clipboard
```

##### 3. Paste the Code from the address bar below
```Powershell
$code = 'xxxxxxxxxxx'
```


##### 4. Obtain the refresh token
 Save the 'Refresh_token' in HelloId to authenticate with API WebRequest

```Powershell
  # Save the 'Refresh_token' in HelloID to authenticate with API WebRequest
  # If Client Secret is required, change the body to example with Client Secret
  $headers = [System.Collections.Generic.Dictionary[[string], [string]]]::new()
  $headers.Add('content-type', 'text/plain')
  $body = "grant_type=authorization_code&code=$code&redirect_uri=$redirect_uri&client_id=$clientID"

  # Example with Client Secret
  #$body = "grant_type=authorization_code&code=$code&redirect_uri=$redirect_uri&client_id=$clientID&client_secret=$clientSecret"
  $response = Invoke-RestMethod "$baseurl/token" -Method 'post' -Headers $headers -Body $body
  $response.refresh_token | Set-Clipboard
```



## Setup the connector

> _How to setup the connector in HelloID._ Are special settings required. Like the _primary manager_ settings for a source connector.

## Getting help

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012557600-Configure-a-custom-PowerShell-source-system) pages_

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
