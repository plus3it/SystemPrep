[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0,ValueFromRemainingArguments=$true)] 
    $RemainingArgs
    ,
	[Parameter(Mandatory=$true,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [string] $SaltWorkingDir
    ,
	[Parameter(Mandatory=$true,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [ValidateScript({ $_ -match "^http[s]?://.*\.zip$" })]
    [string] $SaltInstallerUrl
    ,
	[Parameter(Mandatory=$true,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [ValidateScript({ $_ -match "^http[s]?://.*\.zip$" })]
    [string] $SaltContentUrl
    ,
	[Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [ValidateScript({ $_ -match "^http[s]?://.*\.zip$" })]
    [string[]] $FormulasToInclude
    ,
	[Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [string[]] $FormulaTerminationStrings = "-latest"
    ,
	[Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [ValidateSet("None","MemberServer","DomainController","Workstation")]
    [string] $AshRole = "None"
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [ValidateSet("None","Unclass","NIPR","SIPR","JWICS")]
    [string] $NetBannerLabel = "None"
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [string] $SaltStates = "None"
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [switch] $SourceIsS3Bucket
	,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [string] $AwsRegion
)
#Parameter Descriptions
#$RemainingArgs       #Parameter that catches any undefined parameters passed to the script.
                      #Used by the bootstrapping framework to pass those parameters through to other scripts. 
                      #This way, we don't need to know in the master script all the parameter names for downstream scripts.

#$SaltWorkingDir      #Fully-qualified path to a directory that will be used as a staging location for download and unzip salt content
                      #specified in $SaltContentUrl and any formulas in $FormulasToInclude

#$SaltContentUrl      #Url to a zip file containing the salt installer executable

#$SaltContentUrl      #Url to a zip file containing the `files_root` salt content

#$FormulasToInclude   #Array of strings, where each string is the url of a zipped salt formula to be included in the salt configuration.
                      #Formula content *must* be contained in a zip file.

#$FormulaTerminationStrings = "-latest" #Array of strings
                                        #If an included formula ends with a string in this list, the TerminationString will be removed from the formula name
                                        #Intended to remove versioning information from the formula name
                                        #For example, the formula 'ash-windows-formula-latest' will be renamed to 'ash-windows-formula'

#$AshRole = "None"    #Writes a salt custom grain to the system, ash-windows:role. The role affects the security policies applied. Parameter key:
                      #-- "None"             -- Does not write the custom grain to the system; ash-windows will default to the MemberServer security policy
                      #-- "MemberServer"     -- Ash-windows applies the "MemberServer" security baseline
                      #-- "DomainController" -- Ash-windows applies the "DomainController" security baseline
                      #-- "Workstation"      -- Ash-windows applies the "Workstation" security baseline

#$NetBannerLabel = "None" #Writes a salt custom grain to the system, netbanner:string. Determines the NetBanner string and color configuration. Parameter key:
                           #-- "None"    -- Does not write the custom grain to the system; netbanner will default to the Unclass string
                           #-- "Unclass" -- NetBanner Background color: Green,  Text color: White, String: "UNCLASSIFIED"
                           #-- "NIPR"    -- NetBanner Background color: Green,  Text color: White, String: "UNCLASSIFIED//FOUO"
                           #-- "SIPR"    -- NetBanner Background color: Red,    Text color: White, String: "SECRET AND AUTHORIZED TO PROCESS NATO SECRET"
                           #-- "JWICS"   -- NetBanner Background color: Yellow, Text color: White, String: "TOPSECRET//SI/TK/NOFORN                  **G//HCS//NATO SECRET FOR APPROVED USERS IN SELECTED STORAGE SPACE**"

#$SaltStates = "None" #Comma-separated list of salt states. Listed states will be applied to the system. Parameter key:
                      #-- "None"              -- Special keyword; will not apply any salt states
                      #-- "Highstate"         -- Special keyword; applies the salt "highstate" as defined in the SystemPrep top.sls file
                      #-- "user,defined,list" -- User may pass in a comma-separated list of salt states to apply to the system; state names are case-sensitive and must match exactly

#$SourceIsS3Bucket    #Set to $true if all content to be downloaded is hosted in an S3 bucket and should be retrieved using AWS tools.
#$AwsRegion			  #Set to the region in which the S3 bucket is located.

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

#User variables
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

#Make sure the salt working directories exist
if (-Not (Test-Path $SaltWorkingDir)) { New-Item -Path $SaltWorkingDir -ItemType "directory" -Force > $null; log "Created working directory -- ${SaltWorkingDir}" } else { log "Working directory already exists -- ${SaltWorkingDir}" }

#Create log entry to note the script that is executing
log $ScriptStart
log "Within ${ScriptName} --"
log "SaltWorkingDir = ${SaltWorkingDir}"
log "SaltInstallerUrl = ${SaltInstallerUrl}"
log "SaltContentUrl = ${SaltContentUrl}"
log "FormulasToInclude = ${FormulasToInclude}"
log "FormulaTerminationStrings = ${FormulaTerminationStrings}"
log "AshRole = ${AshRole}"
log "NetBannerLabel = ${NetBannerLabel}"
log "SaltStates = ${SaltStates}"
log "SourceIsS3Bucket = ${SourceIsS3Bucket}"
log "RemainingArgsHash = $(($RemainingArgsHash.GetEnumerator() | % { `"-{0}: {1}`" -f $_.key, $_.value }) -join ' ')"

#Insert script commands
###
#Download and extract the salt installer
$SaltInstallerFile = Download-File -Url $SaltInstallerUrl -SavePath $SaltWorkingDir -SourceIsS3Bucket:$SourceIsS3Bucket -AwsRegion $AwsRegion -Verbose
$SaltInstallerDir = Expand-ZipFile -FileName ${SaltInstallerFile} -DestPath ${SaltWorkingDir} -Verbose

#Download and extract the salt content
$SaltContentFile = Download-File -Url $SaltContentUrl -SavePath $SaltWorkingDir -SourceIsS3Bucket:$SourceIsS3Bucket -AwsRegion $AwsRegion -Verbose
$SaltContentDir = Expand-ZipFile -FileName ${SaltContentFile} -DestPath ${SaltWorkingDir} -Verbose

#Download and extract the salt formulas
foreach ($Formula in $FormulasToInclude) {
    $FormulaFile = Download-File -Url ${Formula} -SavePath $SaltWorkingDir -SourceIsS3Bucket:$SourceIsS3Bucket -AwsRegion $AwsRegion -Verbose
    $FormulaDir = Expand-ZipFile -FileName ${FormulaFile} -DestPath "${SaltWorkingDir}\formulas" -Verbose
	#If the formula directory ends in a string in $FormulaTerminationStrings, delete the string from the directory name
	$FormulaTerminationStrings | foreach { if ($FormulaDir.Name -match "${_}$") { mv $FormulaDir.FullName $FormulaDir.FullName.substring(0,$FormulaDir.FullName.length-$_.length) } }
}

$VcRedistInstaller = (Get-ChildItem "${SaltWorkingDir}" | where {$_.Name -like "vcredist_x64.exe"}).FullName
$SaltInstaller = (Get-ChildItem "${SaltWorkingDir}" | where {$_.Name -like "Salt-Minion-*-Setup.exe"}).FullName
$SaltBase = "C:\salt"
$SaltFileRoot = "${SaltBase}\file_roots"
$SaltBaseEnv = "${SaltFileRoot}\base"
$SaltFormulaRoot = "${SaltBase}\formulas"
$SaltWinRepo = "${SaltFileRoot}\winrepo"
$MinionConf = "${SaltBase}\conf\minion"
$MinionExe = "${SaltBase}\salt-call.exe"
$MinionService = "salt-minion"
$SaltOutputLogFile = "${SaltWorkingDir}\state.output.log"

log "Installing Microsoft Visual C++ 2008 SP1 MFC Security Update redist package -- ${VcRedistInstaller}"
$VcRedistInstallResult = Start-Process -FilePath $VcRedistInstaller -ArgumentList "/q" -NoNewWindow -PassThru -Wait
log "Return code of vcredist install: $(${VcRedistInstallResult}.ExitCode)"

log "Installing salt -- ${SaltInstaller}"
$SaltInstallResult = Start-Process -FilePath $SaltInstaller -ArgumentList "/S" -NoNewWindow -PassThru -Wait
log "Return code of salt install: $(${SaltInstallResult}.ExitCode)"

log "Populating salt file_roots"
mv "${SaltWorkingDir}\file_roots" "${SaltBase}" -Force
log "Populating salt formulas"
mv "${SaltWorkingDir}\formulas" "${SaltBase}" -Force

log "Setting salt-minion configuration to local mode"
cp $MinionConf "${MinionConf}.bak"
#get the contents of the minion's conf file
$MinionConfContent = Get-Content $MinionConf
#set file_client: to "local"
$MinionConfContent = $MinionConfContent | ForEach-Object {$_ -replace "^#file_client: remote","file_client: local"}
#set win_repo_cachfile: to ${SaltWinRepo}\winrepo.p AND set win_repo: to ${SaltWinRepo}
$MinionConfContent = $MinionConfContent | ForEach-Object {$_ -replace "^# win_repo_cachefile: 'salt://win/repo/winrepo.p'","win_repo_cachefile: '${SaltWinRepo}\winrepo.p'`r`nwin_repo: '${SaltWinRepo}'"}
#Construct an array of all the Formula directories to include in the minion conf file
$FormulaFileRootConf = (Get-ChildItem ${SaltFormulaRoot} | where {$_.Attributes -eq "Directory"}) | ForEach-Object { "    - " + $(${_}.fullname) }
#Construct the contents for the file_roots section of the minion conf file
$SaltFileRootConf = @()
$SaltFileRootConf += "file_roots:"
$SaltFileRootConf += "  base:"
$SaltFileRootConf += "    - ${SaltBaseEnv}"
$SaltFileRootConf += "    - ${SaltWinRepo}"
$SaltFileRootConf += $FormulaFileRootConf
$SaltFileRootConf += ""

#Regex strings to mark the beginning and end of the file_roots section
$FilerootsBegin = "^#file_roots:|^file_roots:"
$FilerootsEnd = "^$"

#Find the file_roots section in the minion conf file and replace it with the new configuration in $SaltFileRootConf
$MinionConfContent | foreach -Begin { 
    $n=0; $beginindex=$null; $endindex=$null 
} -Process { 
    if ($_ -match "$FilerootsBegin") { 
        $beginindex = $n 
    }
    if ($beginindex -and -not $endindex -and $_ -match "$FilerootsEnd") { 
        $endindex = $n 
    }
    $n++ 
} -End { 
    $MinionConfContent = $MinionConfContent[0..($beginindex-1)] + $SaltFileRootConf + $MinionConfContent[($endindex+1)..$MinionConfContent.Length]
}

#Write custom grains to the salt configuration file
if ( ($AshRole -ne "None") -or ($NetBannerLabel -ne "None") ) {
    $CustomGrainsContent = @()
    $CustomGrainsContent += "grains:"

    if ($AshRole -ne "None") {
        log "Writing the Ash role to a grain in the salt configuration file"
        $AshRoleCustomGrain = @()
        $AshRoleCustomGrain += "  ash-windows:"
        $AshRoleCustomGrain += "    role: ${AshRole}"
    }
    if ($NetBannerLabel -ne "None") {
        log "Writing the NetBanner label to a grain in the salt configuration file"
        $NetBannerLabelCustomGrain = @()
        $NetBannerLabelCustomGrain += "  netbanner:"
        $NetBannerLabelCustomGrain += "    network_label: ${NetBannerLabel}"
    }

    $CustomGrainsContent += $AshRoleCustomGrain
    $CustomGrainsContent += $NetBannerLabelCustomGrain
    $CustomGrainsContent += ""

    #Regex strings to mark the beginning and end of the custom grains section
    $CustomGrainsBegin = "^#grains:|^grains:"
    $CustomGrainsEnd = "^$"

    #Find the custom grains section in the minion conf file and replace it with the new configuration in $CustomGrainsContent
    $MinionConfContent | foreach -Begin { 
        $n=0; $beginindex=$null; $endindex=$null 
    } -Process { 
        if ($_ -match "$CustomGrainsBegin") { 
            $beginindex = $n 
        }
        if ($beginindex -and -not $endindex -and $_ -match "$CustomGrainsEnd") { 
            $endindex = $n 
        }
        $n++ 
    } -End { 
        $MinionConfContent = $MinionConfContent[0..($beginindex-1)] + $CustomGrainsContent + $MinionConfContent[($endindex+1)..$MinionConfContent.Length]
    }
}

#Write the updated minion conf file to disk
$MinionConfContent | Set-Content $MinionConf

log "Generating salt winrepo cachefile"
$GenRepoResult = Start-Process $MinionExe -ArgumentList "--local winrepo.genrepo" -NoNewWindow -PassThru -Wait

if ("None" -eq $SaltStates) {
    log "Detected the States parameter is set to: ${SaltStates}. Will not apply any salt states."
} elseif ("Highstate" -eq $SaltStates ) {
    log "Detected the States parameter is set to: ${SaltStates}. Applying the salt `"highstate`" to the system."
    $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.highstate --log-file ${SaltOutputLogFile} --log-file-level debug" -NoNewWindow -PassThru -Wait
} else {
    log "Detected the States parameter is set to: ${SaltStates}. Applying the user-defined list of states to the system."
    $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.sls ${SaltStates} --log-file ${SaltOutputLogFile} --log-file-level debug" -NoNewWindow -PassThru -Wait
}
###

#Log exit from script
log "Exiting ${ScriptName} -- salt install complete"
log $ScriptEnd