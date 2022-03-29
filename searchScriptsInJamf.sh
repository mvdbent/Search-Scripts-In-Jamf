#!/bin/bash

# This script is used on an admin computer to search in Jamf Pro scripts which scripts use a specific command.
# It's using the Classic API to search.
# We recommend to have a dedicated user for that search.
# The script does the following:
# 	List all scripts ID
# 	Go through each ID, get the <script_contents_encoded>
# 	Decode the <script_contents_encoded>
# 	Search the string
# 	If contains string, get <name>
# 	Report with script ID and <name>
# 	Report with URL to the script in Jamf Pro
#	Report lines containing the searched value

# Please change the variables according to your needs
serverURL="https://foo.jamfcloud.com"		# i.e.: https://server.domain.tld:port or https://instance.jamfcloud.com
userName="foo"						# it is recommended to create a dedicated read-only user that has read-only access to scripts
userPasswd="foo"

# Check if something is passed as an argument. If nothing is passed, search for python
if [[ "$1" == "" ]]; then
    searchString="python"
else
    searchString="$1"
fi

# Get Jamf Pro version to use token auth if >= 10.35
jamfProVersion=$(curl -s "$serverURL/JSSCheckConnection" | awk -F"." '{ print $1$2 }')

# Encode username and password to use Basic Authorization
encodedAuthorization=$(printf '%s' "$userName:$userPasswd" | /usr/bin/iconv -t ISO-8859-1 | base64)

if [[ "$jamfProVersion" -ge 1035 ]]; then
    bearerTokenFull=$(curl -s -X "POST" "$serverURL/api/v1/auth/token" -H "accept: application/json" -H "Authorization: Basic $encodedAuthorization")
    bearerToken=$( /usr/bin/awk -F \" '{ print $4 }' <<< "$bearerTokenFull" | head -n 2 | tail -n 1 )
    authorizationString="Authorization: Bearer $bearerToken"
else
    authorizationString="Authorization: Basic $encodedAuthorization"
fi

# Get a list of all the scripts
allScripts=$(curl -s -X GET "$serverURL/JSSResource/scripts" -H "accept: application/xml" -H "$authorizationString")

if [[ $(echo "$allScripts" | grep -ic "xml") -eq 0 ]] ; then
    echo "It seems we cannot get data from your server, please check the variables in your script or the credentials used"
    exit
fi

# XSLT to transform the XML make a list of script IDs
XSLT='<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:for-each select="scripts/script">
<xsl:value-of select="id"/>
<xsl:text>&#xa;</xsl:text>
</xsl:for-each>
</xsl:template>
</xsl:stylesheet>'

allScriptsID=$(echo "$allScripts" | xsltproc <(echo "$XSLT") -)

countScripts=$(echo "$allScripts" | xmllint --xpath '/scripts/size/text()' -)

# If we have 0 script, either there is an issue or we don't need that script
# If more than 0, get the correct plural version if needed
if [[ "$countScripts" == 0 ]]; then
    echo "You don't have any scripts in your Jamf Pro instance or we cannot connect, good bye"
    exit 0
elif [[ "$countScripts" == 1 ]]; then
    countScriptsName="script"
else
    countScriptsName="scripts"
fi

# Inform you
echo "You have $countScripts $countScriptsName in your instance of Jamf Pro"
echo "We are looking for: $searchString"
echo ""

while read -r scriptID; do
    
    # Get the full content of the script
    scriptFullInfo=$(curl -s -X GET "$serverURL/JSSResource/scripts/id/$scriptID" -H "$authorizationString")
    
    # Get the decoded version of the script itself
    scriptContentDecoded=$(echo "$scriptFullInfo" | xmllint --xpath 'string(//script/script_contents_encoded)' - | base64 -d)
    
    # Decode the script and search for the number of occurrences of the command
    contentSearch=$(echo "$scriptContentDecoded" | grep -c "$searchString")
    
    # If there is at least 1 occurrences of the command, let's go
    if [[ "$contentSearch" -gt 0 ]]; then
        
        # Get the name of the script
        scriptName=$(echo "$scriptFullInfo" | xmllint --xpath 'string(//script/name)' -)
        
        # Get line numbers showing the searched string, all in one line, separated with spaces
        lineNumbers=$(echo "$scriptContentDecoded" | grep -n "$searchString" | awk -F":" '{ print $1 }' | tr '\n' ' ')
        
        # If more than 0, get the correct plural version if needed
        if [[ "$contentSearch" == 1 ]]; then
            occurenceName="occurrence"
            lineNumbersName="Line that has"
        else
            occurenceName="occurrences"
            lineNumbersName="Lines that have"
        fi
        
        # Let's tell you what we found
        echo "The script called \"$scriptName\" contains $contentSearch $occurenceName of \"$searchString\""
        echo "Script ID is: $scriptID"
        echo "Script URL is: $serverURL/view/settings/computer/scripts/$scriptID"
        echo "$lineNumbersName \"$searchString\": $lineNumbers"
        echo ""
        
    fi
    
done <<< "$allScriptsID"

echo ""
echo "Search is finished, happy $countScriptsName reviewing"
