[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$false,Position=0,ValueFromRemainingArguments=$true)]
    $RemainingArgs
    ,
    [Parameter(Mandatory=$true,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [string] $SaltWorkingDir
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [ValidateScript({ $_ -match "^http[s]?://.*\.(exe|zip)$" })]
    [string] $SaltInstallerUrl="http://docs.saltstack.com/downloads/Salt-Minion-2015.8.1-AMD64-Setup.exe"
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
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
    $EntEnv = $false
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    $OuPath = $false
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [string] $SaltStates = "None"
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [string] $SaltDebugLog
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [string] $SaltResultsLog
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [switch] $SourceIsS3Bucket
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)]
    [string] $AwsRegion
)
#Parameter Descriptions
#$RemainingArgs        #Parameter that catches any undefined parameters passed to the script.
                       #Used by the bootstrapping framework to pass those parameters through to other scripts.
                       #This way, we don't need to know in the master script all the parameter names for downstream scripts.

#$SaltWorkingDir       #Fully-qualified path to a directory that will be used as a staging location for download and unzip salt content
                       #specified in $SaltContentUrl and any formulas in $FormulasToInclude

#$SaltInstallerUrl     #Url to an exe of the salt installer or a zip file containing the salt installer executable

#$SaltContentUrl       #Url to a zip file containing the `files_root` salt content

#$FormulasToInclude    #Array of strings, where each string is the url of a zipped salt formula to be included in the salt configuration.
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

#$EntEnv = $false     #Determines whether to write a salt custom grain, systemprep:enterprise_environment. Parameter key:
                           #-- $false    -- Does not write the custom grain to the system
                           #-- $true     -- TODO: Attempt to detect the enterprise environment from EC2 metadata
                           #-- <string>  -- Sets the grain to the value of $EntEnv

#$OuPath = $false     #Determines whether to write a salt custom grain, join-domain:oupath. If set, and the salt-content.zip
                      #archive contains directives to join the domain, the join-domain formula will place the computer
                      #object in the OU specified by this grain.

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
$RemainingArgsHash = @{}
if ($RemainingArgs) {
    if ($PSVersionTable.PSVersion -eq "2.0") { #PowerShell 2.0 receives remainingargs in a different format than PowerShell 3.0
        $RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($index % 2 -eq 0) { $hash[$_] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }
    }
    else {
        $RemainingArgsHash = $RemainingArgs | ForEach-Object -Begin { $index = 0; $hash = @{} } -Process { if ($_ -match "^-.*:$") { $hash[($_.trim("-",":"))] = $RemainingArgs[$index+1] }; $index++ } -End { Write-Output $hash }
    }
}

###
#Define functions
###
function log {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false,Position=0,ValueFromPipeLine=$true,ValueFromPipeLineByPropertyName=$true)] [string[]]
        $LogMessage,
        [Parameter(Mandatory=$false,Position=1,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$true)] [string]
        $LogTag
    )
    PROCESS {
        foreach ($message in $LogMessage) {
            $date = get-date -format "yyyyMMdd.HHmm.ss"
            "${date}: ${LogTag}: $message" | Out-Default
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
                log -LogTag ${ScriptName} "Downloading file from S3 bucket: ${url_item}"
                $SplitUrl = $url_item.split('/') | where { $_ -notlike "" }
                $BucketName = $SplitUrl[2]
                $Key = $SplitUrl[3..($SplitUrl.count-1)] -join '/'
                $ret = Invoke-Expression "Powershell Read-S3Object -BucketName $BucketName -Key $Key -File $FileName -Region $AwsRegion"
            }
            else {
                log -LogTag ${ScriptName} "Downloading file from HTTP host: ${url_item}"
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
            log -LogTag ${ScriptName} "Unzipping file: ${file}"
            if ($CreateDirFromFileName) { $DestPath = "${DestPath}\$((Get-Item $file).BaseName)" }
            New-Item -Path $DestPath -ItemType Directory -Force -WarningAction SilentlyContinue > $null
            $Shell.namespace($DestPath).copyhere($Shell.namespace("$file").items(), 0x14)
            Write-Output (Get-Item $DestPath)
        }
    }
}


###
#Begin Script
###
# Make sure the salt working directories exist
if (-Not (Test-Path $SaltWorkingDir)) {
    New-Item -Path $SaltWorkingDir -ItemType "directory" -Force > $null
    log -LogTag ${ScriptName} "Created working directory -- ${SaltWorkingDir}"
}
else {
    log -LogTag ${ScriptName} "Working directory already exists -- ${SaltWorkingDir}"
}

# Create log entry to note the script that is executing
log -LogTag ${ScriptName} $ScriptStart
log -LogTag ${ScriptName} "Within ${ScriptName} --"
log -LogTag ${ScriptName} "SaltWorkingDir = ${SaltWorkingDir}"
log -LogTag ${ScriptName} "SaltInstallerUrl = ${SaltInstallerUrl}"
log -LogTag ${ScriptName} "SaltContentUrl = ${SaltContentUrl}"
log -LogTag ${ScriptName} "FormulasToInclude = ${FormulasToInclude}"
log -LogTag ${ScriptName} "FormulaTerminationStrings = ${FormulaTerminationStrings}"
log -LogTag ${ScriptName} "AshRole = ${AshRole}"
log -LogTag ${ScriptName} "EntEnv = ${EntEnv}"
log -LogTag ${ScriptName} "OuPath = ${OuPath}"
log -LogTag ${ScriptName} "SaltStates = ${SaltStates}"
log -LogTag ${ScriptName} "SaltDebugLog = ${SaltDebugLog}"
log -LogTag ${ScriptName} "SaltResultsLog = ${SaltResultsLog}"
log -LogTag ${ScriptName} "SourceIsS3Bucket = ${SourceIsS3Bucket}"
log -LogTag ${ScriptName} "RemainingArgsHash = $(($RemainingArgsHash.GetEnumerator() | % { `"-{0}: {1}`" -f $_.key, $_.value }) -join ' ')"

# Download / extract the salt installer
$SaltInstaller = Download-File -Url $SaltInstallerUrl -SavePath $SaltWorkingDir -SourceIsS3Bucket:$SourceIsS3Bucket -AwsRegion $AwsRegion
if ($SaltInstaller.FullName -match ".*.zip$") {
    $SaltInstallerDir = Expand-ZipFile -FileName ${SaltInstaller} -DestPath ${SaltWorkingDir}
    $SaltInstaller = Get-ChildItem "${SaltWorkingDir}" | where {$_.Name -like "Salt-Minion-*-Setup.exe"}
}

# Download and extract the salt content
if ($SaltContentUrl) {
    $SaltContentFile = Download-File -Url $SaltContentUrl -SavePath $SaltWorkingDir -SourceIsS3Bucket:$SourceIsS3Bucket -AwsRegion $AwsRegion
    $SaltContentDir = Expand-ZipFile -FileName ${SaltContentFile} -DestPath ${SaltWorkingDir}
}

# Download and extract the salt formulas
foreach ($Formula in $FormulasToInclude) {
    $FormulaFile = Download-File -Url ${Formula} -SavePath $SaltWorkingDir -SourceIsS3Bucket:$SourceIsS3Bucket -AwsRegion $AwsRegion
    $FormulaDir = Expand-ZipFile -FileName ${FormulaFile} -DestPath "${SaltWorkingDir}\formulas"
    $FormulaBaseName = ($Formula.split('/')[-1].split('.') | Select-Object -Skip 1 -last 10000000) -join '.'
    $FormulaDir = Get-Item "${FormulaDir}\${FormulaBaseName}"
    # If the formula directory ends in a string in $FormulaTerminationStrings, delete the string from the directory name
    $FormulaTerminationStrings | foreach { if ($FormulaDir.Name -match "${_}$") { mv $FormulaDir.FullName $FormulaDir.FullName.substring(0,$FormulaDir.FullName.length-$_.length) } }
}

$SaltBase = "C:\salt"
$SaltSrv = "C:\salt\srv"
$SaltFileRoot = "${SaltSrv}\states"
$SaltPillarRoot = "${SaltSrv}\pillar"
$SaltBaseEnv = "${SaltFileRoot}\base"
$SaltFormulaRoot = "${SaltSrv}\formulas"
$SaltWinRepo = "${SaltSrv}\winrepo"
$MinionConf = "${SaltBase}\conf\minion"
$MinionExe = "${SaltBase}\salt-call.bat"
$MinionService = "salt-minion"
if (-not $SaltDebugLog) {
    $SaltDebugLogFile = "${SaltWorkingDir}\salt.staterun.debug.log"
}
else {
    $SaltDebugLogFile = $SaltDebugLog
}
if (-not $SaltResultsLog) {
    $SaltResultsLogFile = "${SaltWorkingDir}\salt.staterun.results.log"
}
else {
    $SaltResultsLogFile = $SaltResultsLog
}
$SaltStateArguments = "--out yaml --out-file ${SaltResultsLogFile} --return local --log-file ${SaltDebugLogFile} --log-file-level debug"

log -LogTag ${ScriptName} "Installing salt -- ${SaltInstaller}"
$SaltInstallResult = Start-Process -FilePath $SaltInstaller.FullName -ArgumentList "/S" -NoNewWindow -PassThru -Wait
log -LogTag ${ScriptName} "Return code of salt install: $(${SaltInstallResult}.ExitCode)"

log -LogTag ${ScriptName} "Creating salt directory structure"
mkdir -Force $SaltSrv 2>&1 > $null
mkdir -Force $SaltFormulaRoot 2>&1 > $null
mkdir -Force $SaltPillarRoot 2>&1 > $null

log -LogTag ${ScriptName} "Populating salt file_roots and pillar_roots"
cp "${SaltWorkingDir}\srv" "${SaltBase}" -Force -Recurse 2>&1 | log -LogTag ${ScriptName}
rm "${SaltWorkingDir}\srv" -Force -Recurse 2>&1 | log -LogTag ${ScriptName}
log -LogTag ${ScriptName} "Populating salt formulas"
cp "${SaltWorkingDir}\formulas" "${SaltSrv}" -Force -Recurse 2>&1 | log -LogTag ${ScriptName}
rm "${SaltWorkingDir}\formulas" -Force -Recurse 2>&1 | log -LogTag ${ScriptName}

log -LogTag ${ScriptName} "Setting salt-minion configuration to local mode"
cp $MinionConf "${MinionConf}.bak" 2>&1 | log -LogTag ${ScriptName}
# get the contents of the minion's conf file
$MinionConfContent = Get-Content $MinionConf
# set file_client: to "local"
$MinionConfContent = $MinionConfContent | ForEach-Object {$_ -replace "^#file_client: remote","file_client: local"}
# set win_repo_cachfile: to ${SaltWinRepo}\winrepo.p AND set win_repo: to ${SaltWinRepo}
$MinionConfContent = $MinionConfContent | ForEach-Object {$_ -replace "^# win_repo_cachefile: 'salt://win/repo/winrepo.p'","winrepo_source_dir: 'salt://winrepo'`r`nwinrepo_dir: '${SaltWinRepo}\winrepo'"}
# Construct an array of all the Formula directories to include in the minion conf file
$FormulaFileRootConf = (Get-ChildItem ${SaltFormulaRoot} | where {$_.Attributes -eq "Directory"}) | ForEach-Object { "    - " + $(${_}.fullname) }

log -LogTag ${ScriptName} "Updating the salt file_roots configuration"
# Construct the contents for the file_roots section of the minion conf file
$SaltFileRootConf = @()
$SaltFileRootConf += "file_roots:"
$SaltFileRootConf += "  base:"
$SaltFileRootConf += "    - ${SaltBaseEnv}"
$SaltFileRootConf += "    - ${SaltWinRepo}"
$SaltFileRootConf += $FormulaFileRootConf
$SaltFileRootConf += ""

# Regex strings to mark the beginning and end of the file_roots section
$FileRootsBegin = "^#file_roots:|^file_roots:"
$FileRootsEnd = "^$"

# Find the file_roots section in the minion conf file and replace it with the new configuration in $SaltFileRootConf
$MinionConfContent | foreach -Begin {
    $n=0; $beginindex=$null; $endindex=$null
} -Process {
    if ($_ -match "$FileRootsBegin") {
        $beginindex = $n
    }
    if ($beginindex -and -not $endindex -and $_ -match "$FileRootsEnd") {
        $endindex = $n
    }
    $n++
} -End {
    $MinionConfContent = $MinionConfContent[0..($beginindex-1)] + $SaltFileRootConf + $MinionConfContent[($endindex+1)..$MinionConfContent.Length]
}

log -LogTag ${ScriptName} "Updating the salt pillar_roots configuration"
# Construct the contents for the pillar_roots section of the minion conf file
$SaltPillarRootConf = @()
$SaltPillarRootConf += "pillar_roots:"
$SaltPillarRootConf += "  base:"
$SaltPillarRootConf += "    - ${SaltPillarRoot}"
$SaltPillarRootConf += ""

# Regex strings to mark the beginning and end of the file_roots section
$PillarRootsBegin = "^#pillar_roots:|^pillar_roots:"
$PillarRootsEnd = "^$"

# Find the pillar_roots section in the minion conf file and replace it with the new configuration in $SaltPillarRootConf
$MinionConfContent | foreach -Begin {
    $n=0; $beginindex=$null; $endindex=$null
} -Process {
    if ($_ -match "$PillarRootsBegin") {
        $beginindex = $n
    }
    if ($beginindex -and -not $endindex -and $_ -match "$PillarRootsEnd") {
        $endindex = $n
    }
    $n++
} -End {
    $MinionConfContent = $MinionConfContent[0..($beginindex-1)] + $SaltPillarRootConf + $MinionConfContent[($endindex+1)..$MinionConfContent.Length]
}

# Write the updated minion conf file to disk
$MinionConfContent | Set-Content $MinionConf

# Write custom grains
if ($EntEnv -eq $true) {
    # TODO: Get environment from EC2 metadata or tags
    $EntEnv = 'true'
} elseif ($EntEnv -eq $false) {
    $EntEnv = 'false'
}
log -LogTag ${ScriptName} "Setting systemprep grain..."
$SystemPrepGrain = "grains.setval systemprep `"{'enterprise_environment':'$(${EntEnv}.tolower())'}`""
$SystemPrepGrainResult = Start-Process $MinionExe -ArgumentList "--local ${SystemPrepGrain}" -NoNewWindow -PassThru -Wait
log -LogTag ${ScriptName} "Setting ash-windows grain..."
$AshWindowsGrain = "grains.setval ash-windows `"{'role':'${AshRole}'}`""
$AshWindowsGrainResult = Start-Process $MinionExe -ArgumentList "--local ${AshWindowsGrain}" -NoNewWindow -PassThru -Wait
if ($OuPath) {
    log -LogTag ${ScriptName} "Setting join-domain grain..."
    $JoinDomainGrain = "grains.setval join-domain `"{'join-domain':'${OuPath}'}`""
    $JoinDomainGrainResult = Start-Process $MinionExe -ArgumentList "--local ${JoinDomainGrain}" -NoNewWindow -PassThru -Wait
}

log -LogTag ${ScriptName} "Syncing custom salt modules"
$SyncAllResult = Start-Process $MinionExe -ArgumentList "--local saltutil.sync_all" -NoNewWindow -PassThru -Wait

log -LogTag ${ScriptName} "Generating salt winrepo cachefile"
$GenRepoResult = Start-Process $MinionExe -ArgumentList "--local winrepo.genrepo" -NoNewWindow -PassThru -Wait
$RefreshDbResult = Start-Process $MinionExe -ArgumentList "--local pkg.refresh_db" -NoNewWindow -PassThru -Wait

if ("none" -eq $SaltStates.tolower()) {
    log -LogTag ${ScriptName} "Detected the SaltStates parameter is set to: ${SaltStates}. Will not apply any salt states."
}
else {
    # Run the specified salt state
    if ("highstate" -eq $SaltStates.tolower() ) {
        log -LogTag ${ScriptName} "Detected the States parameter is set to: ${SaltStates}. Applying the salt `"highstate`" to the system."
        $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.highstate ${SaltStateArguments}" -NoNewWindow -PassThru -Wait
        log -LogTag ${ScriptName} "Return code of salt-call: $(${ApplyStatesResult}.ExitCode)"
    }
    else {
        log -LogTag ${ScriptName} "Detected the States parameter is set to: ${SaltStates}. Applying the user-defined list of states to the system."
        $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.sls ${SaltStates} ${SaltStateArguments}" -NoNewWindow -PassThru -Wait
        log -LogTag ${ScriptName} "Return code of salt-call: $(${ApplyStatesResult}.ExitCode)"
    }
    # Check for errors in the results file
    if ((-not (Select-String -Path ${SaltResultsLogFile} -Pattern 'result: false')) -and
        (Select-String -Path ${SaltResultsLogFile} -Pattern 'result: true')) {
        # At least one state succeeded, and no states failed, so log success
        log -LogTag ${ScriptName} "Salt states applied successfully! Details are in the log, ${SaltResultsLogFile}"
    }
    else {
        # One of the salt states failed, log and throw an error
        log -LogTag ${ScriptName} "ERROR: There was a problem running the salt states! Check for errors and failed states in the log file, ${SaltResultsLogFile}"
        throw ("ERROR: There was a problem running the salt states! Check for errors and failed states in the log file, ${SaltResultsLogFile}")
    }
}
###

# Log exit from script
log -LogTag ${ScriptName} "Exiting ${ScriptName} -- salt install complete"
log -LogTag ${ScriptName} $ScriptEnd