# Search-Scripts-In-Jamf

This script is designed to search for a string in all the scripts and or extension attributes in your Jamf Pro instance. It will use the Jamf Pro Classic API to get the list of scripts and iterate through all of them to find the string you’re looking for. The result will show the number of scripts or extension attributes (or both if you use the combined script) containing the string but also for each script the lines and the URL and ID of the element in Jamf Pro.

## General Requirements:

It is recommended to have a specific account that can only read your scripts.

## Settings

Before using the script, there are 3 variables to modify to suit your needs:
- `serverURL` to give the URL of your Jamf Pro server, for example, if you’re hosted in Jamfcloud that would be something like `https://foo.jamfcloud.com`. If you have a specific URL and a specific port, make sure to add it here too.
- `userName` to give the name of the account used to authenticate and access the scripts. As mentioned previously, it is recommended to have a dedicated account for that as the credentials will be in the script in plain text (even if mostly that script will be executed from an admin computer)
- `userPasswd` to give the password of the account

Don’t forget to make the script executable: 
`chmod u+x /path/to/searchScriptsInJamf.sh`

## Usage

Simply execute the script with one parameter being the string you’re looking for. If you don’t have a parameter, the script will search for the occurrences of `python`:

```/path/to/searchScriptsInJamf.sh "dscl"
You have 12 scripts in your instance of Jamf Pro
We are looking for: dscl

The script called "FOO - fv2" contains 7 occurrences of "dscl"
Script ID is: 85
Script URL is: https://foo.jamfcloud.com/view/settings/computer/scripts/85
Lines that have "dscl": 5 50 63 75 81 97 205 

The script called "FOO - Test iclouddnd" contains 3 occurrences of "dscl"
Script ID is: 68
Script URL is: https://foo.jamfcloud.com/view/settings/computer/scripts/68
Lines that have "dscl": 6 8 105 

The script called "Admin Temp" contains 1 occurrence of "dscl"
Script ID is: 31
Script URL is: https://foo.jamfcloud.com/view/settings/computer/scripts/31
Line that has "dscl": 51 


Search is finished, happy scripts reviewing```
