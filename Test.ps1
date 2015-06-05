$VerbosePreference = "Continue"
. .\AnsibleWinModuleGen.ps1
Invoke-AnsibleWinModuleGen -DscResourceName "file" -TargetPath "C:\Users\Trond\Desktop" -TargetModuleName "win_file"

