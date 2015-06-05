Function Invoke-AnsibleWinModuleGen
{
    Param (
        $DscResourceName,
        $dscmodulename,
        $TargetPath,
        $TargetModuleName,
        $HelpObject,
        $CopyrightData, 
        $RequiredDscResourceVersion, 
        $SourceDir = $psscriptroot
        )
    
    $ErrorActionPreference = "Stop"

    #LowerCase for target module name
    $TargetModuleName = $TargetModuleName.tolower()

    #Setup a work folder
    $GenGuid = [system.guid]::NewGuid().tostring()
    $GenPath = Join-Path $env:temp $genguid
    
    New-item -Path $genpath -ItemType directory | out-null
    Write-Verbose "Genpath is $genpath"
    
    $DscResource = Get-DscResource -Name $DscResourceName
    $DscResourceProperties = @()
    $DscResourceProperties += $DscResource.Properties
    
    
    #Strip out the dependson prop, we're not using that in Ansible
    [array]$DscResourceProperties = $DscResourceProperties | where {$_.Name -ne "DependsOn"}
    
    #add empty description/defaultvalue fields
    $DscResourceProperties | foreach {$_ | Add-Member -MemberType NoteProperty -Name Description -Value "" -force}
    $DscResourceProperties | foreach {$_ | Add-Member -MemberType NoteProperty -Name DefaultValue -Value "" -force}

    #Setup the Ansible module (copy placeholder files to $targetPath with names $TargetModuleName.ps1/py)
    
    Copy-item $SourceDir\PlaceHolderFiles\PowerShell1.ps1 -Destination "$GenPath\$TargetModuleName.ps1" -Force
    
    #Add some ansible-specific properties to the resource
    
    
    
    $CredentialObjects = @()
    
    $AutoInstallModuleProp = "" | Select Name, PropertyType, IsMandatory, Values, DefaultValue, Description
    $AutoInstallModuleProp.Name = "AutoInstallModule"
    $AutoInstallModuleProp.PropertyType = "[bool]"
    $AutoInstallModuleProp.IsMandatory = $false
    $AutoInstallModuleProp.DefaultValue = "false"
    $AutoInstallModuleProp.Description = "If true, the required dsc resource/module will be auto-installed using the Powershell package manager"
    $DscResourceProperties += $AutoInstallModuleProp
    
    $AutoSetLcmProp = "" | Select Name, PropertyType, IsMandatory, Values, DefaultValue, Description
    $AutoSetLcmProp.Name = "AutoConfigureLcm"
    $AutoSetLcmProp.PropertyType = "[bool]"
    $AutoInstallModuleProp.DefaultValue = "false"
    $AutoSetLcmProp.IsMandatory = $false
    $AutoSetLcmProp.Description = "If true, LCM will be auto-configured for directly invoking DSC resources (which is a one-time requirement for Ansible DSC modules)"
    $DscResourceProperties += $AutoSetLcmProp
    
    Foreach ($prop in $DscResourceProperties)
    {
        
        $Mandatory = $prop.IsMandatory
        $PropName = $prop.Name

        Write-Verbose "Prop is $propname, mandatory: $mandatory"

        if ($prop.PropertyType -eq "[PSCredential]")
        {
            #Credential object
            Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '#ATTRIBUTE:<PROPNAME>_username;MANDATORY:<MANDATORY>;DEFAULTVALUE:;DESCRIPTION:'
            Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$<PROPNAME>_username = Get-Attr -obj $params -name <PROPNAME>_username -failifempty $<MANDATORY> -resultobj $result'
            Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '#ATTRIBUTE:<PROPNAME>_password;MANDATORY:<MANDATORY>;DEFAULTVALUE:;DESCRIPTION:'
            Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$<PROPNAME>_password = Get-Attr -obj $params -name <PROPNAME>_password -failifempty $<MANDATORY> -resultobj $result'
            
            #Store the credential objects, as we need to parse them into a proper cred object before invoking the dsc resource
            $CredentialObjects += $PropName

            Write-Verbose "Prop $propname is a credential type"
        }
        Else
        {
            Write-Verbose "Prop $propname is not a credential type"
            Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '#ATTRIBUTE:<PROPNAME>;MANDATORY:<MANDATORY>;DEFAULTVALUE:;DESCRIPTION:'
            Add-Content -path "$GenPath\$TargetModuleName.ps1" -Value '$<PROPNAME> = Get-Attr -obj $params -name <PROPNAME> -failifempty $<MANDATORY> -resultobj $result'
        }
        (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<PROPNAME>", $PropName | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
        (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "<MANDATORY>", $Mandatory.ToString() | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
        if (($prop.defaultvalue) -and ($prop.defaultvalue -ne ""))
        {
            Write-Verbose "Defaultvalue is $($prop.defaultvalue)"
            $defaultvalue = $prop.defaultvalue
            (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "DEFAULTVALUE:<", "DEFAULTVALUE:$defaultvalue" | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
        }
        Else
        {
            #(Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "DEFAULTVALUE:<", "DEFAULTVALUE:<NOTHING>" | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
        }

        if (($prop.Description) -and ($prop.Description -ne ""))
        {
            Write-Verbose "Description is $($prop.Description)"
            $Description = $prop.Description
            (Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "DESCRIPTION:<", "DESCRIPTION:$Description" | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
        }
        Else
        {
            #(Get-content -Path "$GenPath\$TargetModuleName.ps1" -Raw) -replace "DESCRIPTION:<", "DESCRIPTION:" | Set-Content -Path "$GenPath\$TargetModuleName.ps1"
        }
        $Description, $defaultvalue = $null
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
if ($<CREDNAME>_username)
{
$<CREDNAME>_securepassword = $<CREDNAME>_password | ConvertTo-SecureString -asPlainText -Force
$<CREDNAME> = New-Object System.Management.Automation.PSCredential($<CREDNAME>_username,$<CREDNAME>_securepassword)
}
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
    
    #TODO: Set add code for switching LCM mode
    
    
    
    #Docs file
    $DocsFilePath = "$GenPath\$TargetModuleName.py"
    Copy-item $SourceDir\PlaceHolderFiles\python1.py -Destination $DocsFilePath -Force
    
    #Populate docs file
    $DocsFileAttributeMatches = @()
    $DocsFileAttributeMatches += get-content "$GenPath\$TargetModuleName.ps1" | Select-String "#ATTRIBUTE"

    $DocsFileAttributes = @()
    Foreach ($match in $DocsFileAttributeMatches)
    {
        $DocsFileAttributes += $match.ToString()
    }

    
    $MetaString =  @'
module: <TARGETMODULENAME>
version_added: <ANSIBLEVERSIONADDED>
short_description: <SHORTDESCRIPTION>
description:
     - <LONGDESCRIPTION>
options:
'@

$MetaString = $MetaString.Replace("<TARGETMODULENAME>", $TargetModuleName)
$MetaString = $MetaString.Replace("<ANSIBLEVERSIONADDED>", $helpobject.AnsibleVersion)
$MetaString = $MetaString.Replace("<SHORTDESCRIPTION>", $helpobject.Shortdescription)
$MetaString = $MetaString.Replace("<LONGDESCRIPTION>", $helpobject.LongDescription)

Add-Content -Path $DocsFilePath -Value $MetaString

<#
    Add-Content -Path $DocsFilePath -Value @'
module: <TARGETMODULENAME>
version_added: <ANSIBLEVERSIONADDED>
short_description: <SHORTDESCRIPTION>
description:
     - <LONGDESCRIPTION>
options:
'@

    (Get-content -Path $DocsFilePath -Raw) -replace "<TARGETMODULENAME>", $TargetModuleName | Set-Content -Path $DocsFilePath
    (Get-content -Path $DocsFilePath -Raw) -replace "<ANSIBLEVERSIONADDED>", $helpobject.AnsibleVersion | Set-Content -Path $DocsFilePath
    (Get-content -Path $DocsFilePath -Raw) -replace "<SHORTDESCRIPTION>", $HelpObject.Shortdescription | Set-Content -Path $DocsFilePath
    (Get-content -Path $DocsFilePath -Raw) -replace "<LONGDESCRIPTION>", $HelpObject.LongDescription | Set-Content -Path $DocsFilePath
#>
    Foreach ($docsattribute in $DocsFileAttributes)
    {
        $docsattributeobj = $docsattribute.split(";")    
        $OptionName = $docsattributeobj[0]
        $OptionName = $OptionName.Replace("#ATTRIBUTE:","")
        
        $IsMandatory = $docsattributeobj[1]
        $IsMandatory = $IsMandatory.Replace("MANDATORY:","")

        $DefaultValue = $docsattributeobj[2]
        $DefaultValue = $DefaultValue.Replace("DEFAULTVALUE:","")
        
        $Description = $docsattributeobj[3]
        $description = $Description.replace("DESCRIPTION:","")

        $OptionAttribute =  @'
  <OPTIONNAME>:
    description:
      - <DESCRIPTION>
    required: <MANDATORY>
    default: <DEFAULTVALUE>
    aliases: []

'@

        $OptionAttribute = $OptionAttribute.Replace("<OPTIONNAME>", $OptionName)
        $OptionAttribute = $OptionAttribute.Replace("<MANDATORY>", $IsMandatory)
        $OptionAttribute = $OptionAttribute.Replace("<DEFAULTVALUE>", $DefaultValue)
        $OptionAttribute = $OptionAttribute.Replace("<DESCRIPTION>", $Description)

        Add-Content -Path $DocsFilePath -Value $OptionAttribute

        <#
       (Get-content -Path $DocsFilePath -Raw) -replace "<OPTIONNAME>", $OptionName | Set-Content -Path $DocsFilePath
       (Get-content -Path $DocsFilePath -Raw) -replace "<MANDATORY>", $Mandatory | Set-Content -Path $DocsFilePath
       (Get-content -Path $DocsFilePath -Raw) -replace "<DEFAULTVALUE>", $DefaultValue | Set-Content -Path $DocsFilePath
       (Get-content -Path $DocsFilePath -Raw) -replace "<DESCRIPTION>", $Description | Set-Content -Path $DocsFilePath
       #>
    }

    #Copy to target
    get-childitem  $GenPath | copy-item -Destination $TargetPath
    
    #Cleanup GenPath
    Remove-item $genpath -recurse -force
}
