#!/bin/bash

# This script is used on an admin computer to search in Jamf Pro extension attributes which of them use a specific command.
# It's using the Classic API to search.
# We recommend to have a dedicated user for that search.
# The script does the following:
# 	List all extension attributes ID
# 	Go through each ID, get the <script> content
# 	Search the string
# 	If contains string, get <name>
# 	Report with extension attributes ID and <name>
# 	Report with URL to the extension attributes in Jamf Pro
#	Report lines containing the searched value

# Please change the variables according to your needs
serverURL="https://foo.jamfcloud.com"       # i.e.: https://server.domain.tld:port or https://instance.jamfcloud.com
userName="foo"                      # it is recommended to create a dedicated read-only user that has read-only access to scripts
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
encodedAuthorization=$(echo -n "$userName:$userPasswd" | /usr/bin/iconv -t ISO-8859-1 | base64)

if [[ "$jamfProVersion" -ge 1035 ]]; then
    bearerTokenFull=$(curl -s -X "POST" "$serverURL/api/v1/auth/token" -H "accept: application/json" -H "Authorization: Basic $encodedAuthorization")
    bearerToken=$( /usr/bin/awk -F \" '{ print $4 }' <<< "$bearerTokenFull" | head -n 2 | tail -n 1 )
    authorizationString="Authorization: Bearer $bearerToken"
else
    authorizationString="Authorization: Basic $encodedAuthorization"
fi

# Get a list of all the extension attributes
allEAs=$(curl -s -X GET "$serverURL/JSSResource/computerextensionattributes" -H "accept: application/xml" -H "$authorizationString")

if [[ $(echo "$allEAs" | grep -ic "xml") -eq 0 ]] ; then
    echo "It seems we cannot get data from your server, please check the variables in your script or the credentials used"
    exit
fi

# XSLT to transform the XML make a list of extension attributes IDs
XSLT='<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text"/>
<xsl:template match="/">
<xsl:for-each select="computer_extension_attributes/computer_extension_attribute">
<xsl:value-of select="id"/>
<xsl:text>&#xa;</xsl:text>
</xsl:for-each>
</xsl:template>
</xsl:stylesheet>'

allEAsID=$(echo "$allEAs" | xsltproc <(echo "$XSLT") -)

countEAs=$(echo "$allEAs" | xmllint --xpath '/computer_extension_attributes/size/text()' -)

# If we have 0 extension attribute, either there is an issue or we don't need that script
# If more than 0, get the correct plural version if needed
if [[ "$countEAs" == 0 ]]; then
    echo "You don't have any extension attributes in your Jamf Pro instance or we cannot connect, good bye"
    exit 0
elif [[ "$countEAs" == 1 ]]; then
    countEAsName="extension attribute"
else
    countEAsName="extension attributes"
fi

# Inform you
echo "You have $countEAs $countEAsName in your instance of Jamf Pro"
echo "We are looking for: $searchString"
echo ""

while read -r extensionAttributeID; do
    
    # Get the full content of the extension attribute
    extensionAttributeFullInfo=$(curl -s -X GET "$serverURL/JSSResource/computerextensionattributes/id/$extensionAttributeID" -H "$authorizationString")
    
    # Get the decoded version of the script itself
    extensionAttributeContentDecoded=$(echo "$extensionAttributeFullInfo" | xmllint --xpath 'string(//computer_extension_attribute/input_type/script)' -)
    
    # Decode the script and search for the number of occurrences of the command
    extensionAttributeContentSearch=$(echo "$extensionAttributeContentDecoded" | grep -c "$searchString")
    
    # If there is at least 1 occurrences of the command, let's go
    if [[ "$extensionAttributeContentSearch" -gt 0 ]]; then
        
        # Get the name of the script
        extensionAttributeName=$(echo "$extensionAttributeFullInfo" | xmllint --xpath 'string(//computer_extension_attribute/name)' -)
        
        # Get line numbers showing the searched string, all in one line, separated with spaces
        extensionAttributeLineNumbers=$(echo "$extensionAttributeContentDecoded" | grep -n "$searchString" | awk -F":" '{ print $1 }' | tr '\n' ' ')
        
        # If more than 0, get the correct plural version if needed
        if [[ "$extensionAttributeContentSearch" == 1 ]]; then
            occurenceName="occurrence"
            lineNumbersName="Line that has"
        else
            occurenceName="occurrences"
            lineNumbersName="Lines that have"
        fi
        
        # Let's tell you what we found
        echo "The extension attribute called \"$extensionAttributeName\" contains $extensionAttributeContentSearch $occurenceName of \"$searchString\""
        echo "EXtention attribute ID is: $extensionAttributeID"
        echo "Extension attribute URL is: $serverURL/computerExtensionAttributes.html?id=$extensionAttributeID"
        echo "$lineNumbersName \"$searchString\": $extensionAttributeLineNumbers"
        echo ""
        
    fi
    
done <<< "$allEAsID"

echo ""
echo "Search is finished, happy $countEAsName reviewing"
