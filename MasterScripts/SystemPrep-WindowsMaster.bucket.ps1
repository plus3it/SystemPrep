[CmdLetBinding()]
Param(
	[Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $Role
)
#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemPrepDir = $env:SystemDrive+"\SystemPrep"
$SystemPrepWorkingDir = $SystemPrepDir+"\WorkingFiles" #Location on the system to download the bucket contents.
$ComputerName = ${Env:computername}
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"

#User variables
$BucketUrl = 'https://systemprep.s3.amazonaws.com'
$IncludeFolders = "Windows/" #Comma-separated list of folders to include. Each folder must end in /. Set to "" to include all folders.
$ExcludeFolders = "" #Comma-separated list of folders to exclude. "" means no exclusions. Exclusions override inclusions.
$IncludeFileExtensions = "" #Comma-separated list of file extensions to include. Set to "" to include all file extensions.
$ExcludeFileExtensions = "html,js" #Comma-separated list of file extensions to exclude. "" means no exclusions. Exclusions override inclusions.
$ScriptsToExecute = @(
                        ,@("https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/SystemPrep-WindowsSaltInstall.ps1","-Role ${Role}")
                     ) #Array of arrays containing the full URL to each script that will be executed, and the parameters to pass to that script. 
                       #Scripts will be downloaded and executed in the order listed. Enter new scripts on a new line that begins with a comma. 
                       #Separate the script and its parameters with a comma. Wrapping the new script and it's parameters in @().

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
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $Url
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string[]] $SaveTo
    )
    PROCESS {
        Write-Output "Saving file -- ${SaveTo}"
        New-Item "${SaveTo}" -ItemType "file" -Force 1> $null
        (new-object net.webclient).DownloadFile("${Url}","${SaveTo}")
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
$A = New-ScheduledTaskAction –Execute "msg.exe" -Argument "* /SERVER:$($ComputerName) $msg"
$T = New-ScheduledTaskTrigger -AtLogon
$P = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel "Highest" -LogonType "ServiceAccount"
$S = New-ScheduledTaskSettingsSet
$D = New-ScheduledTask -Action $A -Principal $P -Trigger $T -Settings $S
$TN = "System Prep Logon Message"
Register-ScheduledTask -TaskName $TN -InputObject $D 2>> $SystemPrepLogFile

#Prepare folder inclusion/exclusion regex strings
log "Preparing regex strings for folder inclusions and exclusions"
$IncludeFolders = $IncludeFolders.split(',') | Sort -unique
$ExcludeFolders = $ExcludeFolders.split(',') | Sort -unique
[regex] $IncludeFoldersRegex = '(?i)(' + (($IncludeFolders | foreach {[regex]::escape($_)}) -join "|") + ')'
[regex] $ExcludeFoldersRegex = '(?i)(' + (($ExcludeFolders | foreach {[regex]::escape($_)}) -join "|") + ')'
log "Folder inclusion regex -- $(${IncludeFoldersRegex}.ToString())"
log "Folder exclusion regex -- $(${ExcludeFoldersRegex}.ToString())"

#Prepare file extension inclusion/exclusion regex strings
log "Preparing regex strings for file extension inclusions and exclusions"
$IncludeFileExtensions = $IncludeFileExtensions.split(',') | Sort -unique
$ExcludeFileExtensions = $ExcludeFileExtensions.split(',') | Sort -unique
[regex] $IncludeFileExtensionsRegex = '(?i)()'
if ($IncludeFileExtensions -ne "") { $IncludeFileExtensionsRegex = '(?i)(' + (($IncludeFileExtensions | foreach {'\.'+[regex]::escape($_)+'$'}) -join "|") + ')' }
[regex] $ExcludeFileExtensionsRegex = '(?i)()'
if ($ExcludeFileExtensions -ne "") { $ExcludeFileExtensionsRegex = '(?i)(' + (($ExcludeFileExtensions | foreach {'\.'+[regex]::escape($_)+'$'}) -join "|") + ')' }
log "File extension inclusion regex -- $(${IncludeFileExtensionsRegex}.ToString())"
log "File extension exclusion regex -- $(${ExcludeFileExtensionsRegex}.ToString())"

#Download S3 bucket source, extract XML, and filter the contents of the S3 Bucket for target folder paths
log "Downloading XML of the S3 bucket: $BucketUrl"
$Html = Invoke-WebRequest $BucketUrl 2>> $SystemPrepLogFile
$Xml = [xml]$Html.Content
$BucketContents = $Xml.ListBucketResult.Contents
log "Filtering XML keys for folder inclusions and exclusions -- Inclusions: $IncludeFolders -- Exclusions: $ExcludeFolders"
$BucketContentsFiltered = $BucketContents | where {$_.Key -match $IncludeFoldersRegex -and ($_.Key -notmatch $ExcludeFoldersRegex -or $ExcludeFolders -contains "")}

#Identify all files in the filtered bucket contents, filtering for target file extension inclusions/exclusions
log "Identifying all files in the filtered XML paths, filtering for file extensions -- Inclusions: $IncludeFileExtensions -- Exclusions: $ExcludeFileExtensions"
$Files = $BucketContentsFiltered | where {$_.Key -notmatch "/$"} | where {$_.Key -match $IncludeFileExtensionsRegex -and ($_.Key -notmatch $ExcludeFileExtensionsRegex -or $ExcludeFileExtensions -contains "")}

#Download and execute each script
foreach ($ScriptObject in $ScriptsToExecute) {
    $Script = $ScriptObject[0]
    $ScriptParams = $ScriptObject[1]
    $Split = $Script[0].split('/') | where { $_ -notlike "" }
    $RelativePath = $Split[2..($Split.count-1)] -join '\'
    $FullPath = "${SystemPrepWorkingDir}\$RelativePath"
    Download-File -Url $Script -SaveTo $FullPath | log 
    log "Calling script -- ${FullPath}"
    Invoke-Expression "& ${FullPath} ${ScriptParams}"
}
#Download all files to the matching directory
#    foreach ($File in $Files) {
#		log "Saving file in working directory -- $($($File).Key)"
#		New-Item "${SystemPrepWorkingDir}\$(${File}.Key)" -ItemType "file" -Force 1> $null
#		(new-object net.webclient).DownloadFile("${BucketUrl}/$(${File}.Key)","${SystemPrepWorkingDir}\$(${File}.Key)")
#	}
#Execute downloaded scripts
#foreach ($script in $ScriptsToExecute) {
#    log "Calling script -- ${script}"
#    Invoke-Expression "& ${script}"
#}
#Removing the scheduled task created earlier
log "Removing the scheduled task notifying users at logon of system customization"
Unregister-ScheduledTask -TaskName $TN -Confirm:$false

log "${ScriptName} complete!"
log $ScriptEnd
