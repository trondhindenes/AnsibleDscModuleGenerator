# AnsibleDscModuleGenerator
A Powershell module for generating Ansible modules from PowerShell DSC resources

### What it does
There is already a tremendous amount of DSC resources available for configuring various aspects of a Windows computer. With the PowerShell 5.0 (Windows Management Framework 5.0), it possible to execute a simple configuration without having to "describe" the entire desired state of the managed computer (through the Invoke-DscConfiguration cmdlet). 

With some plumbing, this enables us to write windows modules for Ansible which map 1-1 with DSC resources - the Ansible module will simply verify parameters, invoke the DSC configuration and record the result and send it back to Ansible.

The Powershell module in this repo auto-generates the required Ansible module for interacting with the underlying DSC resource (the DSC resource will have to be available on the managed node, as the DSC resource itself is not part of the generated Ansible module)


### Prerequisites
The DSC resource which an Ansible module will be generated from needs to be available on the local computer (used for generating the Ansible module).

PowerShell 5.0, which is included in [Windows Management Framework 5.0](https://www.microsoft.com/en-us/download/details.aspx?id=50395) need to be installed on managed nodes.

You can read more about Windows Management Framework 5.0 [here](https://msdn.microsoft.com/en-us/powershell/wmf/releasenotes).  


### Usage
The following example generates an Ansible module from the "file" DSC resource, which is a builtin DSC resource:

	#Enable verbose output    
	$VerbosePreference = "Continue"
	#Import (dot-source) the function
    . .\AnsibleWinModuleGen.ps1
	#Do the thing
    Invoke-AnsibleWinModuleGen -DscResourceName "file" -TargetPath "C:\Ansiblemodules" -TargetModuleName "win_file"

This example will produce a win_file.ps1 and a win_file.py file in the "C:\Ansiblemodules" directory.

    

The following example uses the PowerShell package manager to list all available DSC resources in the Powershell gallery and generates a corresponding Ansible module for each DSC resource.
    
    . .\AnsibleWinModuleGen.ps1
    $ErrorActionPreference = "Stop"
    $VerbosePreference = "Continue"
    $ress = Find-DscResource -Verbose:$false
    $ress = $ress | sort Name
    foreach ($res in $ress)
    {
        write-verbose "Processing $($res.Name)"
        $modulename = $res.ModuleName
        
        #CHeck if we have the latest module installed
        $DownloadModule = $true
        $LocalModule = get-module $modulename -list -ErrorAction SilentlyContinue -Verbose:$false
    
        if ($LocalModule)
        {
            $VersionCheck = $LocalModule.Version.CompareTo($res.Version)
            if ($versioncheck -eq 0)
            {
                Write-verbose "The latest module is already installed locally"
                $DownloadModule = $false
            }
            ElseIf ($versioncheck -eq -1)
            {
                Write-Verbose "The local module is outdated. Upgrading"
            }
        }
    
    
        if ($DownloadModule)
        {
            Write-Verbose "Installing module $modulename"
            Install-Module $modulename -Force -Verbose:$false
    
            #Module should now be available locally
            $LocalModule = get-module $modulename -list -ErrorAction Stop -Verbose:$false
        }
    
        $Description = find-module $modulename -Verbose:$false | select -ExpandProperty Description
        Write-verbose "Adding description:"
        Write-verbose $description
        $helpobject = "" | Select AnsibleVersion,Shortdescription,LongDescription
        $helpobject.Longdescription = $Description
        $helpobject.Shortdescription = "Generated from DSC module $modulename version $($res.Version.ToString())"
        Write-verbose "Generating ansible files"
        Invoke-AnsibleWinModuleGen -DscResourceName $res.Name -TargetPath "C:\AnsibleModules" -TargetModuleName "win_$($res.Name)" -HelpObject $helpobject
        Write-verbose ""
        Write-verbose ""
        $description = $null
    }





        
    
    
    
    
    

### Using the Ansible module
The generated Ansible module can be used like any other Ansible module, either by copying them into the "modules\windows" directory on the control node (where Ansible is installed), or by using the "ANSIBLE_LIBRARY" env variable. 

For instance, if the generated modules are placed in ~/windows_generated directory, use the following command to make sure Ansible searches this directory when looking for valid modules:

    export ANSIBLE_LIBRARY=~/windows_generated

Use the generated .py file to find which options(parameters) are required and which are not. In addition to the parameter exposed by the DSC resource, two extra options are added to the Ansible module:



- AutoInstallModule: If true, this will attempt to auto-download the Powershell module  containig the needed DSC resource from the PowerShell gallery if it's not already installed.
- AutoConfigureLcm: In order to enable the use of Invoke-DscResource, LCM refresh mode needs to be set to "Disabled". This disables any use of push/pull server functionality for DSC. When set to true, LCM will be auto-configured on the node. This is a one-time setting, and has a slight time penalty if set to true for each Ansible play.

### Modules galore
Ansible modules are generated from time to time for all available DSC resources in the PowerShell gallery. These can be found here (this is done by the second example script above): [https://github.com/trondhindenes/Ansible-Auto-Generated-Modules](https://github.com/trondhindenes/Ansible-Auto-Generated-Modules)
