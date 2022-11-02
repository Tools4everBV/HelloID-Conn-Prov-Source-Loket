# Obtain Loket refesh token
# Follow the staps below (step by step)
# Supplier documentation can be found here: https://developer.loket.nl/OauthCode

# -------------------------------
# 1. Fill in the parameters of your tenant
# Have the Loket user available with access to the required Loket employer.
$clientID = 'xxxx'
$clientSecret = 'xxxx'                      #  When used change the Body in Step 4
$redirect_uri = 'https://loket.nl'          #
$baseurl = 'https://oauth.loket-acc.nl'     #  https://oauth.loket-acc.nl   // https://oauth.loket.nl
# -------------------------------


# -------------------------------
# 2. Generate URL and paste the URL into the Browser
#       A log in screen appears.
#       Log in with the Loket User (incl. Possible second factor when configured)
#       After a successfull login, copy the code from the address bar https://www.loket.nl/?state=1234&code= {{ZW5rOEdwUnVhN3c0ZW42VEt5}}

$url = "$baseurl/authorize?client_id=$clientID&redirect_uri=$redirect_uri&response_type=code&scope=all&state=1234"
$url | Set-Clipboard
# -------------------------------


# -------------------------------
# 3. Paste the Code from the address bar below
$code = 'xxxxxxxxxxx'
# -------------------------------


# -------------------------------
# 4. Run the following code to obtain the Refresh_Token
#       Save the 'Refresh_token' in HelloID to authenticate with API WebRequest
#       If Client Secret is required, change the body to example with Client Secret
$headers = [System.Collections.Generic.Dictionary[[string], [string]]]::new()
$headers.Add('content-type', 'text/plain')
$body = "grant_type=authorization_code&code=$code&redirect_uri=$redirect_uri&client_id=$clientID"

# Example with Client Secret
#$body = "grant_type=authorization_code&code=$code&redirect_uri=$redirect_uri&client_id=$clientID&client_secret=$clientSecret"

$response = Invoke-RestMethod "$baseurl/token" -Method 'post' -Headers $headers -Body $body
$response.refresh_token | Set-Clipboard
# -------------------------------


