[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0,ValueFromRemainingArguments=$true)] $RemainingArgs,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [switch] $NoReboot
)
#Parameter Descriptions
#$RemainingArgs       #Parameter that catches any undefined parameters passed to the script.
                      #Used by the bootstrapping framework to pass those parameters through to other scripts. 
                      #This way, we don't need to know in advance all the parameter names for downstream scripts.
                      
#$NoReboot            #Switch to disable the system reboot. By default, the master script will reboot the system when the script is complete.

#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemPrepDir = "${env:SystemDrive}\SystemPrep"
$SystemPrepWorkingDir = "${SystemPrepDir}\WorkingFiles" #Location on the system to download the bucket contents.
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"
$RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($_ -match "^-.*:$") { $hash[($_.trim("-",":"))] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }

#User variables
$ScriptsToExecute = @(
                        @{
                            ScriptUrl  = "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1"
                            Parameters = $RemainingArgsHash
                         }
                     ) #Array of hashtables (key-value dictionaries). Each hashtable has two keys, ScriptUrl and Parameters. 
                       # -- ScriptUrl  -- The full path to the PowerShell script to download and execute.
                       # -- Parameters -- Must be a hashtable of parameters to pass to the script. 
                       #                  Use $RemainingArgsHash to inherit any unassigned parameters that are passed to the Master script.
                       #To download and execute additional scripts, create a new hashtable for each script and place it on a new line
                       #in the array.
                       #Hastables are of the form @{ ScriptUrl = {https://your.host/your.script}; Parameters = {"-yourParam yourValue"}
                       #Scripts must be written in PowerShell.
                       #Scripts will be downloaded and executed in the order listed. 

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
log "NoReboot = ${NoReboot}"
log "RemainingArgsHash = $(($RemainingArgsHash.GetEnumerator() | % { `"-{0}: {1}`" -f $_.key, $_.value }) -join ' ')"

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
    $Script = $ScriptObject["ScriptUrl"]
    $ScriptParams = $ScriptObject["Parameters"]
    $Split = $Script.split('/') | where { $_ -notlike "" }
    $RelativePath = $Split[2..($Split.count-1)] -join '\'
    $FullPath = "${SystemPrepWorkingDir}\$RelativePath"
    Download-File -Url $Script -SaveTo $FullPath 2>&1 | log
    log "Calling script -- ${FullPath}"
    Invoke-Expression "& ${FullPath} @ScriptParams"
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
