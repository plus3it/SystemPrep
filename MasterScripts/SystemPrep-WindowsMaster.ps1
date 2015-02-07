[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0,ValueFromRemainingArguments=$true)] 
    $RemainingArgs
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [switch] $SourceIsS3Bucket
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [switch] $NoReboot
)
#Parameter Descriptions
#$RemainingArgs       #Parameter that catches any undefined parameters passed to the script.
                      #Used by the bootstrapping framework to pass those parameters through to other scripts. 
                      #This way, we don't need to know in advance all the parameter names for downstream scripts.

#$SourceIsS3Bucket    #Set to $true if all content to be downloaded is hosted in an S3 bucket and should be retrieved using AWS tools.
#$NoReboot            #Switch to disable the system reboot. By default, the master script will reboot the system when the script is complete.

#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemPrepDir = "${env:SystemDrive}\SystemPrep"
$SystemPrepWorkingDir = "${SystemPrepDir}\WorkingFiles" #Location on the system to download the bucket contents.
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"
#Convert RemainingArgs to a hashtable, so the arguments can be passed to other scripts via a parameter splat
if ($PSVersionTable.PSVersion -eq "2.0") { #PowerShell 2.0 receives remainingargs in a different format than PowerShell 3.0
	$RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($index % 2 -eq 0) { $hash[$_] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }
} else {
	$RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($_ -match "^-.*:$") { $hash[($_.trim("-",":"))] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }
}

Function Join-Hashtables {
#credit http://powershell.org/wp/2013/01/23/join-powershell-hash-tables/
    [CmdLetBinding()]
    Param (
    [hashtable]$First, 
    [hashtable]$Second, 
    [switch]$Force
    )

    #create clones of hashtables so originals are not modified
    $Primary = $First.Clone()
    $Secondary = $Second.Clone()

    #check for any duplicate keys
    $duplicates = $Primary.keys | where {$Secondary.ContainsKey($_)}
    if ($duplicates) {
        foreach ($item in $duplicates) {
            if ($force) {
                #force primary key, so remove secondary conflict
                $Secondary.Remove($item)
            }
            else {
                Write-Host "Duplicate key $item" -ForegroundColor Yellow
                Write-Host "A $($Primary.Item($item))" -ForegroundColor Yellow
                Write-host "B $($Secondary.Item($item))" -ForegroundColor Yellow
                $r = Read-Host "Which key do you want to KEEP [AB]?"
                if ($r -eq "A") {
                    $Secondary.Remove($item)
                }
                elseif ($r -eq "B") {
                    $Primary.Remove($item)
                }
                Else {
                    Write-Warning "Aborting operation"
                    Return 
                }
            } #else prompt
       }
    }

    #join the two hash tables
    $Primary+$Secondary

} #end Join-Hashtable

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
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $SaveTo,
        [Parameter(Mandatory=$false,Position=2,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [switch] $SourceIsS3Bucket
    )
    PROCESS {
        if ($SourceIsS3Bucket) {
            Write-Output "Downloading from S3 bucket and saving to: ${SaveTo}"
            $SplitUrl = $Url.split('/') | where { $_ -notlike "" }
            $BucketName = $SplitUrl[2]
            $Key = $SplitUrl[3..($SplitUrl.count-1)] -join '/'
            Read-S3Object -BucketName $BucketName -Key $Key -File $SaveTo 2>&1
        }
        else {
            Write-Output "Downloading from HTTP host and saving to: ${SaveTo}"
            New-Item "${SaveTo}" -ItemType "file" -Force > $null
            (new-object net.webclient).DownloadFile("${Url}","${SaveTo}") 2>&1
        }
    }
}

#User variables
$ScriptsToExecute = @(
                        @{
                            ScriptUrl  = "https://s3.amazonaws.com/systemprep/SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1"
                            Parameters = (Join-Hashtables $RemainingArgsHash  @{ 
                                                                                  SaltWorkingDir = "${SystemPrepWorkingDir}\Salt" 
                                                                                  SaltInstallerUrl = "https://s3.amazonaws.com/systemprep/SystemContent/Windows/Salt/salt-installer.zip" 
                                                                                  SaltContentUrl = "https://s3.amazonaws.com/systemprep/SystemContent/Windows/Salt/salt-content.zip" 
                                                                                  FormulasToInclude = @(
                                                                                                        "https://s3.amazonaws.com/salt-formulas/ash-windows-formula-latest.zip",
                                                                                                        "https://s3.amazonaws.com/salt-formulas/dotnet4-formula-master.zip"
                                                                                                        "https://s3.amazonaws.com/salt-formulas/emet-formula-master.zip",
                                                                                                        "https://s3.amazonaws.com/salt-formulas/netbanner-formula-master.zip"
                                                                                                       )
                                                                                  FormulaTerminationStrings = @( "-latest", "-master" )
                                                                                  AshRole = "MemberServer"
                                                                                  NetBannerLabel = "Unclass"
                                                                                  SaltStates = "Highstate"
                                                                                  SourceIsS3Bucket = $SourceIsS3Bucket
                                                                                } -Force 
                                         )
                         }
                     ) #Array of hashtables (key-value dictionaries). Each hashtable has two keys, ScriptUrl and Parameters. 
                       # -- ScriptUrl  -- The full path to the PowerShell script to download and execute.
                       # -- Parameters -- Must be a hashtable of parameters to pass to the script. 
                       #                  Use $RemainingArgsHash to inherit any unassigned parameters that are passed to the Master script.
                       #                  Use `Join-Hashtables $firsthash $secondhash -Force` to merge two hash tables (first overrides duplicate keys in second)
                       #To download and execute additional scripts, create a new hashtable for each script and place it on a new line
                       #in the array.
                       #Hastables are of the form @{ ScriptUrl = "https://your.host/your.script"; Parameters = @{yourParam = "yourValue"} }
                       #Scripts must be written in PowerShell.
                       #Scripts will be downloaded and executed in the order listed. 

#Make sure the system prep and working directories exist
if (-Not (Test-Path $SystemPrepDir)) { New-Item -Path $SystemPrepDir -ItemType "directory" -Force > $null; log "Created SystemPrep directory -- ${SystemPrepDir}" } else { log "SystemPrep directory already exists -- $SystemPrepDir" }
if (-Not (Test-Path $SystemPrepWorkingDir)) { New-Item -Path $SystemPrepWorkingDir -ItemType "directory" -Force > $null; log "Created working directory -- ${SystemPrepWorkingDir}" } else { log "Working directory already exists -- ${SystemPrepWorkingDir}" }

#Create log entry to note the script name
log $ScriptStart
log "Within ${ScriptName} -- Beginning system preparation"
log "SourceIsS3Bucket = ${SourceIsS3Bucket}"
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
    $FileName = $Split[($Split.Count-1)]
    $FullPath = "${SystemPrepWorkingDir}\$FileName"
    Download-File -Url $Script -SaveTo $FullPath -SourceIsS3Bucket:$SourceIsS3Bucket 2>&1 | log
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
