. .\AnsibleWinModuleGen.ps1
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"
$ress = Find-DscResource -Verbose:$false
$Modules = $ress | Select -ExpandProperty modulename -Unique
$BadModules = get-content .\BadModules.json -Raw | ConvertFrom-Json
$ress = $ress | sort Name
foreach ($Module in $Modules)
{
    
    write-verbose "Processing $Module"
    $modulename = $Module
    $OnlineModule = Find-Module $ModuleName
    $IsBad = $false
    Foreach ($BadModule in $BadModules)
    {
        if ($Module -like "$BadModule")
        {
            $IsBad = $true
        }
    }
    
    if ($Isbad -eq $true)
    {
        Write-output "Bad module"
    }
    Else
    {
            #CHeck if we have the latest module installed
            $DownloadModule = $true
            $LocalModule = get-module $modulename -list -ErrorAction SilentlyContinue -Verbose:$false

            if ($LocalModule)
            {
                if ($localmodule.count -gt 1)
                {
                    $localmodule = $localmodule | Sort-Object version -Descending | select -first 1
                }
                $VersionCheck = $LocalModule.Version.CompareTo($OnlineModule.Version)
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
                Install-Module $modulename -Force -Verbose:$false -Scope Currentuser

                #Module should now be available locally
                $LocalModule = get-module $modulename -list -ErrorAction Stop -Verbose:$false
            }

            
            foreach ($res in $ress | where {$_.ModuleName -eq $module})
            {
                write-verbose "Processing $($res.Name) in module $Module"
                $modulename = $res.ModuleName.ToLower()
                
                #CHeck if we have the latest module installed
                <#
                $DownloadModule = $true
                $LocalModule = get-module $modulename -list -ErrorAction SilentlyContinue -Verbose:$false

                if ($LocalModule)
                {
                    if ($localmodule.count -gt 1)
                    {
                        $localmodule = $localmodule | Sort-Object version -Descending | select -first 1
                    }
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
                    Install-Module $modulename -Force -Verbose:$false -Scope Currentuser

                    #Module should now be available locally
                    $LocalModule = get-module $modulename -list -ErrorAction Stop -Verbose:$false
                }
                #>
                $Description = find-module $modulename -Verbose:$false | select -ExpandProperty Description
                Write-verbose "Adding description:"
                Write-verbose $description
                $helpobject = "" | Select AnsibleVersion,Shortdescription,LongDescription
                $helpobject.Longdescription = $Description
                $helpobject.Shortdescription = "Generated from DSC module $modulename version $($res.Version.ToString()) at $((get-date).tostring())"
                Write-verbose "Generating ansible module files"
                Invoke-AnsibleWinModuleGen -DscResourceName $res.Name -TargetPath "C:\AnsibleModules\$modulename" -TargetModuleName ("win_$($res.Name)").ToLower() -HelpObject $helpobject  -erroraction "Continue"
                if ($downloadmodule)
                {
                    <#
                    write-verbose "Removing module $modulename"
                    remove-item ($LocalModule.ModuleBase) -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable RemoveErr
                    
                    if ($RemoveErr)
                    {
                        Write-warning "Could not remove module $modulename"
                    }
                    #>
                    $ModulesToRemove += $modulename
                }
                Write-verbose ""
                Write-verbose ""
                $description = $null
            }
            
            if ($downloadmodule)
                {
                    
                    write-verbose "Removing module $modulename"
                    Uninstall-Module $modulename
                    
                    <#
                    remove-item ($LocalModule.ModuleBase) -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable RemoveErr
                    
                    if ($RemoveErr)
                    {
                        Write-warning "Could not remove module $modulename"
                    }
                    #>
                    
                }
        
    }
    

}

<#
Foreach ($modulename in $ModulesToRemove)
{
    write-verbose "Removing module $modulename"
    remove-item ($LocalModule.ModuleBase) -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable RemoveErr
    
    if ($RemoveErr)
    {
        Write-warning "Could not remove module $modulename"
    }
}
#>


