# This script is used on an admin computer to search in Jamf Pro scripts which scripts use a specific command.
# It's using the Classic API to search.
# We recommend to have a dedicated user for that search.
# The script does the following:
#   List all scripts ID
#   Go through each ID, get the <script_contents_encoded>
#   Decode the <script_contents_encoded>
#   Search the string
#   If contains string, get <name>
#   Report with script ID and <name>
#   Report with URL to the script in Jamf Pro
#   Report lines containing the searched value

# Please change the variables according to your needs
$serverURL = ""     # i.e.: https://server.domain.tld:port or https://instance.jamfcloud.com
$userName = ""                      # it is recommended to create a dedicated read-only user that has read-only access to scripts
$userPasswd = ""

Clear-Host

# Removes last / in URL if added, not a blocker, just an esthetical issue if displaying URLs
If ( $serverURL -match '\/$' ) {

    $serverURL = $serverURL -replace ".$"

}

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
$jamfProVersion = ((Invoke-RestMethod $serverURL/JSSCheckConnection).Split(".")[0,1]) -join ""

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

# Get a list of all the scripts

# Build a specific URL
$allScriptsParams = @{
    Uri = "$serverURL/JSSResource/scripts";
    Method = 'GET';
    Authorization = $authorizationString;
    accept = "application/xml"
}

# Use the authentication and URL
$allScripts = CatchInvokeRestMethodErrors @allScriptsParams

# Get ID of each script
$allScriptsID = $allScripts.scripts.script.id

# Get count of number of scripts
$countScripts = $allScripts.scripts.size


# If we have 0 script, either there is an issue or we don't need that script
# If more than 0, get the correct plural version if needed

If ( $countScripts -eq 0 ) {
    Write-Host "You don't have any scripts in your Jamf Pro instance or we cannot connect, good bye" -ForegroundColor Green
    Break
} ElseIf ( $countScripts -eq 1 ) {
    $countScriptsName = "script"
} Else {
    $countScriptsName = "scripts"
}

# Inform you
Write-Host "You have $countScripts $countScriptsName in your instance of Jamf Pro" -ForegroundColor Green
Write-Host "We are looking for: $searchString" -ForegroundColor Green
Write-Host ""


# Let's go through all the scripts and get info 
foreach ($scriptID in $allScriptsID)
{
    # Build a specific URL
    $scriptIDParams = @{
        Uri = "$serverURL/JSSResource/scripts/id/$scriptID";
        Method = 'GET';
        Authorization = $authorizationString;
        accept = "application/xml"
    }
    
    # Use the authentication and URL
    $scriptFullInfo = CatchInvokeRestMethodErrors @scriptIDParams

    $scriptContentDecoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($scriptFullInfo.script.script_contents_encoded))

    $contentSearch = (Select-String -pattern $searchString -InputObject $scriptContentDecoded -AllMatches).Matches.Count
    
    # If there is at least 1 occurrences of the command, let's go
    If ( $contentSearch -gt 0) {
        # Get the name of the script
        $scriptName = $scriptFullInfo.script.name

        # Get line numbers showing the searched string, all in one line, separated with spaces
        # Create object and insert each line into it
        $outItems = New-Object System.Collections.Generic.List[System.Object]
        
        # For each line of the script, add to the object
        $scriptContentDecoded.Split("`n") | ForEach-Object {
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

        If ( $contentSearch -eq 1 ) {
            $occurenceName="occurrence"
            $lineNumbersName="Line that has"
        } Else {
            $occurenceName="occurrences"
            $lineNumbersName="Line that have"
        }
        Write-Host "The script called ""$scriptName"" contains $contentSearch $occurenceName of $searchString"
        Write-Host "Script ID is:" $scriptID
        Write-Host "Script URL is:" $serverURL/view/settings/computer/scripts/$scriptID
        Write-Host $lineNumbersName $searchString":" $lineNumbers
        Write-Host
    }
}

Write-Host
Write-Host "Search is finished, happy $countScriptsName reviewing"
