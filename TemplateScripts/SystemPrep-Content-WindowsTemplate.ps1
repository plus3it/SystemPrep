[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0,ValueFromRemainingArguments=$true)] 
    $RemainingArgs
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [switch] $SourceIsS3Bucket

#    ,
#	[Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
#   [ValidateSet("value1","value2","etc")]
#   [string] $ParamName
)
#Parameter Descriptions
#$RemainingArgs       #Parameter that catches any undefined parameters passed to the script.
                      #Used by the bootstrapping framework to pass those parameters through to other scripts. 
                      #This way, we don't need to know in advance all the parameter names for downstream scripts.

#$SourceIsS3Bucket    #Set to $true if all content to be downloaded is hosted in an S3 bucket and should be retrieved using AWS tools.

#$ParamName           #ParamDescription...

#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemPrepDir = "${env:SystemDrive}\SystemPrep"
$SystemPrepWorkingDir = $SystemPrepDir+"\WorkingFiles" #Location on the system to download the bucket contents.
$SystemRoot = $env:SystemRoot
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"
$RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($_ -match "^-.*:$") { $hash[($_.trim("-",":"))] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }
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
log "RemainingArgsHash = $(($RemainingArgsHash.GetEnumerator() | % { `"-{0}: {1}`" -f $_.key, $_.value }) -join ' ')"

#Insert script commands
###
Download-File -Url $PackageUrl -SaveTo "${TemplateWorkingDir}\${PackageFile}" | log
Expand-ZipFile -FileName ${PackageFile} -SourcePath ${TemplateWorkingDir} -DestPath ${TemplateWorkingDir}

###

#Log exit from script
log "Exiting ${ScriptName} --"
log $ScriptEnd