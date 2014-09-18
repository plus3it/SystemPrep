[CmdLetBinding()]
Param(
	[Parameter(Mandatory=$false,Position=0,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $Role="None",
    [Parameter(Mandatory=$false,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $Network="Unclass",
    [Parameter(Mandatory=$false,Position=2,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $States="None",
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [switch] $NoReboot
)
#Parameters
#$Role = "None"       #Writes a salt custom grain to the system, ash-windows:role. The role affects the security policies applied. Parameter key:
                      #-- "None"             -- Does not write the custom grain to the system; ash-windows will default to the MemberServer security policy
                      #-- "MemberServer"     -- Ash-windows applies the "MemberServer" security baseline
                      #-- "DomainController" -- Ash-windows applies the "DomainController" security baseline
                      #-- "Workstation"      -- Ash-windows applies the "Workstation" security baseline

#$Network = "Unclass" #Writes a salt custom grain to the system, netbanner:network. Determines the NetBanner string and color configuration. Invalid values default back to "Unclass". Parameter key:
                      #-- "Unclass" -- NetBanner Background color: Green,  Text color: White, String: "UNCLASSIFIED"
                      #-- "NIPR"    -- NetBanner Background color: Green,  Text color: White, String: "UNCLASSIFIED//FOUO"
                      #-- "SIPR"    -- NetBanner Background color: Red,    Text color: White, String: "SECRET AND AUTHORIZED TO PROCESS NATO SECRET"
                      #-- "JWICS"   -- NetBanner Background color: Yellow, Text color: White, String: "TOPSECRET//SI/TK/NOFORN                  **G//HCS//NATO SECRET FOR APPROVED USERS IN SELECTED STORAGE SPACE**"

#$States = "None" #Comma-separated list that determines which salt states to apply to the system. Parameter key:
                  #-- "None"              -- Special case; will not apply any salt state
                  #-- "Highstate"         -- Special case; applies the salt "highstate" as defined in the SystemPrep top.sls file
                  #-- {user-defined-list} -- User may pass in a comma-separated list of salt states to apply to the system; state names are case-sensitive and must match exactly

#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemPrepDir = "${env:SystemDrive}\SystemPrep"
$SystemPrepWorkingDir = "${SystemPrepDir}\WorkingFiles" #Location on the system to download the bucket contents.
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"

#User variables
$ScriptsToExecute = @(
                        ,@("https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1","-Role ${Role} -States ${States} -Network ${Network}")
                     ) #Array of arrays containing the full URL to each script that will be executed, and the parameters to pass to that script. 
                       #Scripts will be downloaded and executed in the order listed. Enter new scripts on a new line that begins with a comma. 
                       #Separate the script and its parameters with a comma. Enclose the script url and the parameters in quotes. Wrap the new 
                       #script and its parameters in @() to identify it as an array.

function log {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $LogMessage
    )
    PROCESS {
        #Writes the input $LogMessage to the output for capture by the bootstrap script.
        Write-Output "${Scriptname}: $LogMessage"
    }
}

function Download-File {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string] $Url,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $SaveTo
    )
    PROCESS {
        Write-Output "Saving file -- ${SaveTo}"
        New-Item "${SaveTo}" -ItemType "file" -Force 1> $null
        (new-object net.webclient).DownloadFile("${Url}","${SaveTo}") 2>&1 | log
    }
}

#Make sure the system prep and working directories exist
if (-Not (Test-Path $SystemPrepDir)) { New-Item -Path $SystemPrepDir -ItemType "directory" -Force 1>$null; log "Created SystemPrep directory -- ${SystemPrepDir}" } else { log "SystemPrep directory already exists -- $SystemPrepDir" }
if (-Not (Test-Path $SystemPrepWorkingDir)) { New-Item -Path $SystemPrepWorkingDir -ItemType "directory" -Force 1>$null; log "Created working directory -- ${SystemPrepWorkingDir}" } else { log "Working directory already exists -- ${SystemPrepWorkingDir}" }

#Create log entry to note the script name
log $ScriptStart
log "Within ${ScriptName} -- Beginning system preparation"

#Create an atlogon scheduled task to notify users that system customization is in progress
log "Registering a scheduled task to notify users at logon that system customization is in progress"
$msg = "Please wait... System customization is in progress. The system will reboot automatically when customization is complete."
$taskname = "System Prep Logon Message"
if ($PSVersionTable.psversion.major -ge 4) {
    $A = New-ScheduledTaskAction –Execute "msg.exe" -Argument "* /SERVER:%computername% $msg"
    $T = New-ScheduledTaskTrigger -AtLogon
    $P = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel "Highest" -LogonType "ServiceAccount"
    $S = New-ScheduledTaskSettingsSet
    $D = New-ScheduledTask -Action $A -Principal $P -Trigger $T -Settings $S
    Register-ScheduledTask -TaskName $taskname -InputObject $D 2>&1 | log
} else {
    invoke-expression "& $env:systemroot\system32\schtasks.exe /create /SC ONLOGON /RL HIGHEST /NP /V1 /RU SYSTEM /F /TR `"msg * /SERVER:%computername% ${msg}`" /TN `"${taskname}`"" 2>&1 | log
}

#Download and execute each script
foreach ($ScriptObject in $ScriptsToExecute) {
    $Script = $ScriptObject[0]
    $ScriptParams = $ScriptObject[1]
    $Split = $Script.split('/') | where { $_ -notlike "" }
    $RelativePath = $Split[2..($Split.count-1)] -join '\'
    $FullPath = "${SystemPrepWorkingDir}\$RelativePath"
    Download-File -Url $Script -SaveTo $FullPath 2>&1 | log
    log "Calling script -- ${FullPath}"
    Invoke-Expression "& ${FullPath} ${ScriptParams}"
}

log "Removing the scheduled task notifying users at logon of system customization"
invoke-expression "& ${env:systemroot}\system32\schtasks.exe /delete /f /TN `"System Prep Logon Message`"" 2>&1 | log

if ($NoReboot) {
    log "Detected NoReboot switch. System will not be rebooted."
} else {
    log "Reboot scheduled. System will reboot in 30 seconds."
    invoke-expression "& ${env:systemroot}\system32\shutdown.exe /r /t 30 /d p:2:4 /c `"SystemPrep complete. Rebooting computer.`"" 
}

log "${ScriptName} complete!"
log $ScriptEnd
