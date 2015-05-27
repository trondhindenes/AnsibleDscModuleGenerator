Param ($DscResourceName,$dscmodulename,$TargetPath,$TargetModuleName,$HelpObject,$CopyrightData, $RequiredDscResourceVersion)

#Setup a work folder
$GenGuid = [system.guid]::NewGuid().tostring()
$GenPath = Join-Path $env:temp $genguid

New-item -Path $genpath -ItemType directory | out-null

$DscResource = Get-DscResource -Name $DscResourceName
$DscResourceProperties = $DscResource.Properties


#Strip out the dependson prop, we're not using that in Ansible
$DscResourceProperties = $DscResourceProperties | where {$_.Name -ne "DependsOn"}

#Setup the Ansible module (copy placeholder files to $targetPath with names $TargetModuleName.ps1/py)
Copy-item $SourceDir\PlaceHolderFiles\PowerShell1.ps1 -Destination "$GenPath\$TargetModuleName.ps1" -Force

#Add some ansible-specific properties to the resource



$CredentialObjects = @()

$AutoInstallModuleProp = "" | Select Name, PropertyType, IsMandatory, Values
$AutoInstallModuleProp.Name = "AutoInstallModule"
$AutoInstallModuleProp.PropertyType = "[bool]"
$AutoInstallModuleProp.IsMandatory = $false
$DscResourceProperties += $AutoInstallModuleProp

$AutoSetLcmProp = "" | Select Name, PropertyType, IsMandatory, Values
$AutoSetLcmProp.Name = "AutoConfigureLcm"
$AutoSetLcmProp.PropertyType = "[bool]"
$AutoSetLcmProp.IsMandatory = $false
$DscResourceProperties += $AutoSetLcmProp

Foreach ($prop in $DscResourceProperties)
{
    $Mandatory = $prop.IsMandatory
    $PropName = $prop.Name
    if ($prop.PropertyType -eq "[PSCredential]")
    {
        #Credential object
        Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '#ATTRIBUTE:<PROPNAME>_username,MANDATORY:<MANDATORY>,DEFAULTVALUE:,DESCRIPTION:'
        Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$<PROPNAME>_username = Get-Attr -obj $params -name <PROPNAME>_username -failifempty $<MANDATORY> -resultobj $result'
        Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '#ATTRIBUTE:<PROPNAME>_password,MANDATORY:<MANDATORY>,DEFAULTVALUE:,DESCRIPTION:'
        Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$<PROPNAME>_password = Get-Attr -obj $params -name <PROPNAME>_password -failifempty $<MANDATORY> -resultobj $result'
        
        #Store the credential objects, as we need to parse them into a proper cred object before invoking the dsc resource
        $CredentialObjects += $PropName
    }
    Else
    {
        Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '#ATTRIBUTE:<PROPNAME>_password,MANDATORY:<MANDATORY>,DEFAULTVALUE:,DESCRIPTION:'
        Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$<PROPNAME> = Get-Attr -obj $params -name <PROPNAME> -failifempty $<MANDATORY> -resultobj $result'
    }
    (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<PROPNAME>", $PropName | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
    (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<MANDATORY>", ($Mandatory.ToString()) | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
}

#For properties that have valid values, ensure that the supplied params are valid:
$PropsWithValues = $DscResourceProperties | where {($_.Values.count) -gt 0}
foreach ($Prop in $PropsWithValues)
{
    $PropName = $prop.Name
    $Values = $prop.Values

    Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value @'
If ($<PROPNAME>)
{
    If ((<VALIDVALUES>) -contains $<PROPNAME> ) {
    }
    Else
    {
        Fail-Json $result "Option <PropName> has invalid value $<PROPNAME>. Valid values are <VALIDVALUES>"
    }
}
'@
    $ValuesString = ""
    Foreach ($value in $values)
        {
            $ValuesString += "'" + $value + "'"
            $ValuesString += ","
        }
    $ValuesString = $ValuesString.trim(",")
    
    (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<VALIDVALUES>", $ValuesString | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
    (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<PROPNAME>", $PropName | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
}

#Take care of the Credential things
Foreach ($credobject in $CredentialObjects)
{
    
    #Take the _username and _password strings and mash them togheter in a happy PsCredentialObject
    Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value @'
$<CREDNAME>_securepassword = $<CREDNAME>_password | ConvertTo-SecureString -asPlainText -Force
$<CREDNAME> = New-Object System.Management.Automation.PSCredential($<CREDNAME>_username,$<CREDNAME>_securepassword)
'@
    (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<CREDNAME>", $credobject | Set-Content -Path "$GenPath\$TargetModuleName.ps1"

}


#Remove blank lines
#(get-content "$GenPath\$TargetModuleName.ps1") | where {$_.Trim() -ne ""} | Set-Content "$GenPath\$TargetModuleName.ps1"

#At this point we need the dsc resource to exist on the target node
Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$DscResourceName = "<DscResourceName>"'
(Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<DscResourceName>", $DscResourceName | Set-Content -Path "$GenPath\$TargetModuleName.ps1"

if ($RequiredDscResourceVersion)
{
Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$RequiredDscResourceVersion = "<RequiredDscResourceVersion>"'
(Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<RequiredDscResourceVersion>", $RequiredDscResourceVersion | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
}

if ($dscmodulename)
{
Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$dscmodulename = "<dscmodulename>"'
(Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<dscmodulename>", $dscmodulename | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
}

#Copy in the powershell2_dscresourceverify.ps1 into the file
Get-content "$SourceDir\PlaceHolderFiles\powershell2_dscresourceverify.ps1" -Raw | Add-Content "$GenPath\$TargetModuleName.ps1"

Get-content "$SourceDir\PlaceHolderFiles\powershell3_dscparser.ps1" -Raw | Add-Content "$GenPath\$TargetModuleName.ps1"



#Docs file
Copy-item $SourceDir\PlaceHolderFiles\python1.py -Destination "$GenPath\$TargetModuleName.py" -Force