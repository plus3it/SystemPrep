[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0,ValueFromRemainingArguments=$true)] 
    $RemainingArgs
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [switch] $SourceIsS3Bucket
	,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [string] $AwsRegion

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
#$AwsRegion			  #Set to the region in which the S3 bucket is located.

#$ParamName           #ParamDescription...

#System variables
$ScriptName = $MyInvocation.mycommand.name
$SystemRoot = $env:SystemRoot
$ScriptStart = "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
$ScriptEnd = "--------------------------------------------------------------------------------"
#Convert RemainingArgs to a hashtable
if ($PSVersionTable.PSVersion -eq "2.0") { #PowerShell 2.0 receives remainingargs in a different format than PowerShell 3.0
	$RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($index % 2 -eq 0) { $hash[$_] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }
} else {
	$RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($_ -match "^-.*:$") { $hash[($_.trim("-",":"))] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }
}###
###

#User variables
$PackageUrl = ""
$TemplateWorkingDir = ""

###

function log {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $LogMessage
    )
    PROCESS {
		foreach ($message in $LogMessage) {
			#Writes the input $LogMessage to the output for capture by the bootstrap script.
			Write-Output "${Scriptname}: $message"
		}
    }
}

function Download-File {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $Url,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $SavePath,
        [Parameter(Mandatory=$false,Position=2,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [switch] $SourceIsS3Bucket,
        [Parameter(Mandatory=$false,Position=3,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $AwsRegion
    )
	BEGIN {
		New-Item -Path ${SavePath} -ItemType Directory -Force -WarningAction SilentlyContinue > $null
	}
    PROCESS {
		foreach ($url_item in $Url) {
			$FileName = "${SavePath}\$((${url_item}.split('/'))[-1])"
			if ($SourceIsS3Bucket) {
				Write-Verbose "Downloading file from S3 bucket: ${url_item}"
				$SplitUrl = $url_item.split('/') | where { $_ -notlike "" }
				$BucketName = $SplitUrl[2]
				$Key = $SplitUrl[3..($SplitUrl.count-1)] -join '/'
				$ret = Invoke-Expression "Powershell Read-S3Object -BucketName $BucketName -Key $Key -File $FileName -Region $AwsRegion"
			}
			else {
				Write-Verbose "Downloading file from HTTP host: ${url_item}"
				(new-object net.webclient).DownloadFile("${url_item}","${FileName}")
			}
			Write-Output (Get-Item $FileName)
		}
    }
}

function Expand-ZipFile {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]] $FileName,
        [Parameter(Mandatory=$true,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [string] $DestPath,
        [Parameter(Mandatory=$false,Position=2,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] [switch] $CreateDirFromFileName
    )
    PROCESS {
		foreach ($file in $FileName) {
			$Shell = new-object -com shell.application
			if (!(Test-Path "$file")) {
				throw "$file does not exist" 
			}
			Write-Verbose "Unzipping file: ${file}"
			if ($CreateDirFromFileName) { $DestPath = "${DestPath}\$((Get-Item $file).BaseName)" }
			New-Item -Path $DestPath -ItemType Directory -Force -WarningAction SilentlyContinue > $null
			$Shell.namespace($DestPath).copyhere($Shell.namespace("$file").items(), 0x14) 
			Write-Output (Get-Item $DestPath)
		}
	}
}

#Create log entry to note the script that is executing
log $ScriptStart
log "Within ${ScriptName} --"
log "RemainingArgsHash = $(($RemainingArgsHash.GetEnumerator() | % { `"-{0}: {1}`" -f $_.key, $_.value }) -join ' ')"

#Insert script commands
###
$PackageFile = Download-File -Url $PackageUrl -SavePath "${TemplateWorkingDir}" -SourceIsS3Bucket:$SourceIsS3Bucket -AwsRegion $AwsRegion -Verbose
$PackageDir = Expand-ZipFile -FileName ${PackageFile} -DestPath -DestPath ${TemplateWorkingDir} -Verbose

###

#Log exit from script
log "Exiting ${ScriptName} --"
log $ScriptEnd