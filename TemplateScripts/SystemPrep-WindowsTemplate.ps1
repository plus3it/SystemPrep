[CmdLetBinding()]
#Param(
#	[Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $ParamName
#)

#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemPrepDir = $env:SystemDrive+"\SystemPrep"
$SystemPrepWorkingDir = $SystemPrepDir+"\WorkingFiles" #Location on the system to download the bucket contents.
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"
###

#User variables
$PackageUrl = ""
$TemplateWorkingDir = "${SystemPrepWorkingDir}\SystemContent\........."
$PackageFile = (${PackageUrl}.split('/'))[-1]

###

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
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $Url,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string[]] $SaveTo
    )
    PROCESS {
        Write-Output "Saving file -- ${SaveTo}"
        New-Item "${SaveTo}" -ItemType "file" -Force 1> $null
        (new-object net.webclient).DownloadFile("${Url}","${SaveTo}")
    }
}

function Expand-ZipFile {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $FileName,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $SourcePath,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $DestPath
    )
    $Shell = new-object -com shell.application
    if (!(Test-Path "$SourcePath\$FileName"))
    {
        throw "$SourcePath\$FileName does not exist" 
    }
    New-Item -ItemType Directory -Force -Path $DestPath -WarningAction SilentlyContinue
    $Shell.namespace($DestPath).copyhere($Shell.namespace("$SourcePath\$FileName").items(), 0x14) 
}

#Make sure the system prep and working directories exist
if (-Not (Test-Path $SystemPrepDir)) { New-Item -Path $SystemPrepDir -ItemType "directory" -Force 1>$null; log "Created SystemPrep directory -- ${SystemPrepDir}" } else { log "SystemPrep directory already exists -- $SystemPrepDir" }
if (-Not (Test-Path $SystemPrepWorkingDir)) { New-Item -Path $SystemPrepWorkingDir -ItemType "directory" -Force 1>$null; log "Created working directory -- ${SystemPrepWorkingDir}" } else { log "Working directory already exists -- ${SystemPrepWorkingDir}" }

#Create log entry to note the script that is executing
log $ScriptStart
log "Within ${ScriptName} --"

#Insert script commands
###
Download-File -Url $PackageUrl -SaveTo "${TemplateWorkingDir}\${PackageFile}" | log
Expand-ZipFile -FileName ${PackageFile} -SourcePath ${TemplateWorkingDir} -DestPath ${TemplateWorkingDir}

###

#Log exit from script
log "Exiting ${ScriptName} --"
log $ScriptEnd