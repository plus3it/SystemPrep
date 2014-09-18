[CmdLetBinding()]
Param(
	[Parameter(Mandatory=$false,Position=0,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $Role="None",
    [Parameter(Mandatory=$false,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $Network="Unclass",
    [Parameter(Mandatory=$false,Position=2,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $States="None",
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [switch] $NoReboot
)

#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemPrepDir = "${env:SystemDrive}\SystemPrep"
$SystemPrepWorkingDir = $SystemPrepDir+"\WorkingFiles" #Location on the system to download the bucket contents.
$SystemRoot = $env:SystemRoot
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"
###

#User variables
$SaltWorkingDir = "${SystemPrepWorkingDir}\SystemContent\Windows\Salt"
$PackageUrl = "https://systemprep.s3.amazonaws.com/SystemContent/Windows/Salt/salt-content.zip"
$FormulasToInclude = @(
                        "https://salt-formulas.s3.amazonaws.com/ash-windows-formula-latest.zip"
                     ) #Array containing the full URL to each salt formula zip file to be included in the salt configuration.
                       #Enter new formulas on a new line, separating them from the previous URL with a comma.

$FormulaTerminationStrings = "-latest" #Comma-separated list of strings
                                       #If an included formula ends with a string in this list, the TerminationString will be removed from the formula name
                                       #Intended to remove versioning information from the formula name
                                       #For example, the formula 'ash-windows-formula-latest' will be renamed to 'ash-windows-formula'
###

function log {
	[CmdLetBinding()]
	Param(
		[Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $LogMessage
	)
	PROCESS {
		#Writes the input $LogMessage to the output for capture by the bootstrap script.
		Write-Output "${ScriptName}: $LogMessage"
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

function Expand-ZipFile {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $FileName,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $SourcePath,
        [Parameter(Mandatory=$true,Position=2,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $DestPath
    )
    $Shell = new-object -com shell.application
    if (!(Test-Path "$SourcePath\$FileName"))
    {
        throw "$SourcePath\$FileName does not exist" 
    }
    New-Item -ItemType Directory -Force -Path $DestPath -WarningAction SilentlyContinue 1> $null
    $Shell.namespace($DestPath).copyhere($Shell.namespace("$SourcePath\$FileName").items(), 0x14) 
}

#Make sure the system prep and working directories exist
if (-Not (Test-Path $SystemPrepDir)) { New-Item -Path $SystemPrepDir -ItemType "directory" -Force 1>$null; log "Created SystemPrep directory -- ${SystemPrepDir}" } else { log "SystemPrep directory already exists -- $SystemPrepDir" }
if (-Not (Test-Path $SystemPrepWorkingDir)) { New-Item -Path $SystemPrepWorkingDir -ItemType "directory" -Force 1>$null; log "Created working directory -- ${SystemPrepWorkingDir}" } else { log "Working directory already exists -- ${SystemPrepWorkingDir}" }

#Create log entry to note the script that is executing
log $ScriptStart
log "Within ${ScriptName} --"
log "Role = ${Role}"

#Insert script commands
###
$PackageFile = (${PackageUrl}.split('/'))[-1]
Download-File -Url $PackageUrl -SaveTo "${SaltWorkingDir}\${PackageFile}" | log
Expand-ZipFile -FileName ${PackageFile} -SourcePath ${SaltWorkingDir} -DestPath ${SaltWorkingDir}

foreach ($Formula in $FormulasToInclude) {
    $FormulaFile = (${Formula}.split('/'))[-1]
    Download-File -Url $Formula -SaveTo "${SaltWorkingDir}\${FormulaFile}" | log
    Expand-ZipFile -FileName ${FormulaFile} -SourcePath ${SaltWorkingDir} -DestPath "${SaltWorkingDir}\formulas"
}

#If the formula directory ends in a string in $FormulaTerminationStrings, delete the string from the directory name
$FormulaTerminationStrings = $FormulaTerminationStrings.split(',')
$FormulaDirs = Get-ChildItem -Path "${SaltWorkingDir}\formulas" -Directory
foreach ($FormulaDir in $FormulaDirs) {
    $FormulaTerminationStrings | foreach { if ($FormulaDir.Name -match "${_}$") { mv $FormulaDir.FullName $FormulaDir.FullName.substring(0,$FormulaDir.FullName.length-$_.length) } }
}

$SaltInstaller = (Get-ChildItem "${SaltWorkingDir}" | where {$_.Name -like "Salt-Minion-*-Setup.exe"}).FullName
$SaltBase = "C:\salt"
$SaltFileRoot = "${SaltBase}\file_roots"
$SaltFormulaRoot = "${SaltBase}\formulas"
$SaltWinRepo = "${SaltFileRoot}\winrepo"
$MinionConf = "${SaltBase}\conf\minion"
$MinionExe = "${SaltBase}\salt-call.exe"
$MinionService = "salt-minion"

log "Installing salt -- ${SaltInstaller}"
$InstallResult = Start-Process $SaltInstaller -ArgumentList "/S" -NoNewWindow -PassThru -Wait

log "Populating salt file_roots"
mv "${SystemPrepWorkingDir}\SystemContent\Windows\Salt\file_roots" "${SaltBase}" -Force
log "Populating salt formulas"
mv "${SystemPrepWorkingDir}\SystemContent\Windows\Salt\formulas" "${SaltBase}" -Force

#Construct a string of all the Formula directories to include in the minion conf file
$FormulaFileRootConf = ((Get-ChildItem ${SaltFormulaRoot} -Directory) | ForEach-Object { "    - " + $(${_}.fullname) + "`r`n" }) -join ''

log "Setting salt-minion configuration to local mode"
cp $MinionConf "${MinionConf}.bak"
#set file_client: to "local"
(Get-Content $MinionConf) | ForEach-Object {$_ -replace "^#file_client: remote","file_client: local"} | Set-Content $MinionConf
#set win_repo_cachfile: to ${SaltWinRepo}\winrepo.p AND set win_repo: to ${SaltWinRepo}
(Get-Content $MinionConf) | ForEach-Object {$_ -replace "^# win_repo_cachefile: 'salt://win/repo/winrepo.p'","win_repo_cachefile: '${SaltWinRepo}\winrepo.p'`r`nwin_repo: '${SaltWinRepo}'"} | Set-Content $MinionConf
#set file_roots: base: to ${SaltFileRoot} and ${SaltFormulaRoot}
(Get-Content $MinionConf -raw) -replace '(?mi)(.*)^# Default:[\r\n]+#file_roots:[\r\n]+#  base:[\r\n]+#    - /srv/salt(.*)', "$1# Default:`r`nfile_roots:`r`n  base:`r`n    - ${SaltFileRoot}`r`n$FormulaFileRootConf$2" | Set-Content $MinionConf

#Write custom grains to the salt configuration file
if ($Role -ne "None") {
    log "Writing the server role to a grain in the salt configuration file"
    (Get-Content $MinionConf -raw) -replace '(?mi)(.*)grains:(.*)', "${1}grains:`r`n  ash-windows:`r`n    role: ${Role}`r`n`r`n${2}" | Set-Content $MinionConf
    (Get-Content $MinionConf -raw) -replace '(?mi)(.*)^#grains:(.*)', "${1}grains:`r`n${2}" | Set-Content $MinionConf
}
if ($Network -ne "None") {
    log "Writing the network to a grain in the salt configuration file"
    (Get-Content $MinionConf -raw) -replace '(?mi)(.*)grains:(.*)', "${1}grains:`r`n  netbanner:`r`n    network: ${Network}`r`n${2}" | Set-Content $MinionConf
    (Get-Content $MinionConf -raw) -replace '(?mi)(.*)^#grains:(.*)', "${1}grains:`r`n${2}" | Set-Content $MinionConf
}

log "Generating salt winrepo cachefile"
$GenRepoResult = Start-Process $MinionExe -ArgumentList "--local winrepo.genrepo" -NoNewWindow -PassThru -Wait

log "Restarting salt-minion service"
(Get-Service -name $MinionService) | Stop-Service -PassThru | Start-Service

if ($States -eq "None") {
    log "Detected the States parameter is set to: ${States}. Will not apply any salt states."
} elseif ($States -eq "Highstate") {
    log "Detected the States parameter is set to: ${States}. Applying the salt `"highstate`" to the system."
    $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.highstate" -NoNewWindow -PassThru -Wait
} else {
    log "Detected the States parameter is set to: ${States}. Applying the user-defined list of states to the system."
    $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.sls ${States}" -NoNewWindow -PassThru -Wait
}
###

#Log exit from script
log "Exiting ${ScriptName} -- salt install complete"
log $ScriptEnd