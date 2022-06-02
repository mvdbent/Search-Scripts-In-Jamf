# This script is used on an admin computer to search in Jamf Pro extension attributes which of them use a specific command.
# It's using the Classic API to search.
# We recommend to have a dedicated user for that search.
# The script does the following:
#   List all extension attributes ID
#   Go through each ID, get the <script> content
#   Search the string
#   If contains string, get <name>
#   Report with extension attributes ID and <name>
#   Report with URL to the extension attributes in Jamf Pro
#   Report lines containing the searched value

# Please change the variables according to your needs
$serverURL = ""     # i.e.: https://server.domain.tld:port or https://instance.jamfcloud.com
$userName = ""                      # it is recommended to create a dedicated read-only user that has read-only access to scripts
$userPasswd = ""


Clear-Host

If ( [string]::IsNullOrEmpty($serverURL) ) {
        Write-Host "We don't have a serverURL..."
        Write-Host "Please enter your Jamf Pro URL (include https:// and :port if needed)" -ForegroundColor Green
        $serverUrl = Read-Host

        Write-Host "The URL you typed is: $serverURL"
}

If ( [string]::IsNullOrEmpty($userName) ) {
        Write-Host "We don't have a username..."
        Write-Host "Please enter your Jamf Pro username" -ForegroundColor Green
        $userName = Read-Host

        Write-Host "The username you typed is: $userName"
}


If ( [string]::IsNullOrEmpty($userPasswd) ) {
        Write-Host "We don't have a password..."
        Write-Host "Please enter your Jamf Pro password" -ForegroundColor Green
        # asks securely
        $userPasswdSecured = Read-Host -AsSecureString
        $userPasswd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($userPasswdSecured))

        Write-Host "The password you typed is: NO, I won't show..."
}

# Let's ask for the search string
Write-Host "What string do you want to search in your scripts (press Enter to search for python): " -NoNewLine -ForegroundColor Green
$searchString = Read-Host

# If user does not enter anything, we search for python
If ( [string]::IsNullOrEmpty($searchString) ) {
    $searchString = "python"
}

Write-Host "The search string is: $searchString"
Write-Host

Function CatchInvokeRestMethodErrors {
    Param
    (
        #Parameters
        [Parameter(
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "URI of server")]
        [String]$uri,
    
        [Parameter(
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Method")]
        [String]$Method,
    
        [Parameter(
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "Authorization",
            Position = 0)]
        [String]$Authorization,

        [Parameter(
            Mandatory = $true,
            ValueFromPipelineByPropertyName = $true,
            HelpMessage = "accept",
            Position = 0)]
        [String]$accept
        
    )

    Try {
        $invokeRestMethodParams = @{
            uri = "$uri";
            Method = $Method;
            Headers = @{ 
                Authorization = $Authorization;
                accept = "$accept"
            }
        }
        Invoke-RestMethod @invokeRestMethodParams
    } Catch {
        # Dig into the exception to get the Response details.
        Write-Host "StatusCode:" $_.Exception.Response.StatusCode.value__ 
        Write-Host "It seems we cannot get data from your server, please check the variables in your script or the credentials used"
        Break
    }
}

# Get Jamf Pro version to use token auth if >= 10.35
$jamfProVersion = (Invoke-RestMethod $serverURL/JSSCheckConnection | %{$_.Split(".")[0,1]}) -join ""

# Prepare for token acquisition
$combineCreds = "$($userName):$($userPasswd)"
$encodeCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($CombineCreds))
$basicAuthValue = "Basic $EncodeCreds"

If ( $jamfProVersion -ge 1035) {
    # Get Token for auth
    $tokenParams = @{
        uri = "$serverURL/api/v1/auth/token";
        Method = 'POST';
        Authorization = $basicAuthValue;
        accept = "application/json"
    }

    # Extract token
    $bearerTokenFull = CatchInvokeRestMethodErrors @tokenParams
    $bearerToken = $bearerTokenFull.token

    # Create Authorization String for Bearer
    $authorizationString = "Bearer $bearerToken"
} else {
    # Create Authorization String for Basic
    $authorizationString = "Basic $EncodeCreds"
}

###################################################################################

# Get a list of all the extension attributes

# Build a specific URL
$allEAsParams = @{
    Uri = "$serverURL/JSSResource/computerextensionattributes";
    Method = 'GET';
    Authorization = $authorizationString;
    accept = "application/xml"
}

# Use the authentication and URL
$allEAs = CatchInvokeRestMethodErrors @allEAsParams

# Get ID of each extension attribute
$allEAsID = $allEAs.computer_extension_attributes.computer_extension_attribute.id

# Get count of number of extension attributes
$countEAs = $allEAs.computer_extension_attributes.size

# If we have 0 extension attribute, either there is an issue or we don't need that script
# If more than 0, get the correct plural version if needed
If ( $countEAs -eq 0 ) {
    Write-Host "You don't have any extension attributes in your Jamf Pro instance or we cannot connect, good bye" -ForegroundColor Green
    Break
} ElseIf ( $countEAs -eq 1 ) {
    $countEAsName = "extension attribute"
} Else {
    $countEAsName = "extension attributes"
}

# Inform you
Write-Host "You have $countEAs $countEAsName in your instance of Jamf Pro" -ForegroundColor Green
Write-Host "We are looking for: $searchString" -ForegroundColor Green
Write-Host ""


# Let's go through all the extension attributes and get info
foreach ($extensionAttributeID in $allEAsID)
{
    # Build a specific URL
    $eaIDParams = @{
        Uri = "$serverURL/JSSResource/computerextensionattributes/id/$extensionAttributeID";
        Method = 'GET';
        Authorization = $authorizationString;
        accept = "application/xml"
    }
    
    # Use the authentication and URL
    $extensionAttributeFullInfo = CatchInvokeRestMethodErrors @eaIDParams

    $extensionAttributeContentDecoded = $extensionAttributeFullInfo.computer_extension_attribute.input_type.script
    
    $extensionAttributeContentSearch = (Select-String -pattern $searchString -InputObject $extensionAttributeContentDecoded -AllMatches).Matches.Count
    
    # If there is at least 1 occurrences of the command, let's go
    If ( $extensionAttributeContentSearch -gt 0) {
        # Get the name of the script
        $extensionAttributeName = $extensionAttributeFullInfo.computer_extension_attribute.name

        # Get line numbers showing the searched string, all in one line, separated with spaces
        # Create object and insert each line into it
        $outItems = New-Object System.Collections.Generic.List[System.Object]
        
        # For each line of the script, add to the object
        $extensionAttributeContentDecoded.Split("`n") | ForEach-Object {
            $outItems.Add("$_")
        }

        # Create empty counter to act as line number
        $counter = 0
        
        # Go through each object and get "line number" of the desired string
        $lineNumbers = ($outItems | ForEach-Object {
        
            # Increment counter
            $counter++
        
            # Search for the specific string
            $validVar = Select-String -Pattern $searchString -InputObject $_
        
            # If content of search is not empty (i.e. we found the string) we get the "line number"
            If ( -Not [string]::IsNullOrEmpty($validVar) ) {
                $counter
            }
        }) -join ' '

        If ( $extensionAttributeContentSearch -eq 1 ) {
            $occurenceName="occurrence"
            $lineNumbersName="Line that has"
        } Else {
            $occurenceName="occurrences"
            $lineNumbersName="Line that have"
        }
        Write-Host "The extension attribute called ""$extensionAttributeName"" contains $extensionAttributeContentSearch $occurenceName of $searchString"
        Write-Host "EXtention attribute ID is: $extensionAttributeID"
        Write-Host "Extension attribute URL is: $serverURL/computerExtensionAttributes.html?id=$extensionAttributeID"
        Write-Host $lineNumbersName $searchString":" $lineNumbers
        Write-Host
    }
}

Write-Host
Write-Host "Search is finished, happy $countEAsName reviewing"
