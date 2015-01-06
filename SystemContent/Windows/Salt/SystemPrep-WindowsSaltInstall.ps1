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
    [string] $NetBannerString = "None"
    ,
    [Parameter(Mandatory=$false,ValueFromPipeLine=$false,ValueFromPipeLineByPropertyName=$false)] 
    [string] $SaltStates = "None"
)
#Parameter Descriptions
#$RemainingArgs       #Parameter that catches any undefined parameters passed to the script.
                      #Used by the bootstrapping framework to pass those parameters through to other scripts. 
                      #This way, we don't need to know in the master script all the parameter names for downstream scripts.

#$SaltWorkingDir      #Fully-qualified path to a directory that will be used as a staging location for download and unzip salt content
                      #specified in $SaltContentUrl and any formulas in $FormulasToInclude

#$SaltContentUrl      #Url to a zip file containing the salt installer executable and the files_root salt content

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

#$NetBannerString = "None" #Writes a salt custom grain to the system, netbanner:string. Determines the NetBanner string and color configuration. Parameter key:
                           #-- "None"    -- Does not write the custom grain to the system; netbanner will default to the Unclass string
                           #-- "Unclass" -- NetBanner Background color: Green,  Text color: White, String: "UNCLASSIFIED"
                           #-- "NIPR"    -- NetBanner Background color: Green,  Text color: White, String: "UNCLASSIFIED//FOUO"
                           #-- "SIPR"    -- NetBanner Background color: Red,    Text color: White, String: "SECRET AND AUTHORIZED TO PROCESS NATO SECRET"
                           #-- "JWICS"   -- NetBanner Background color: Yellow, Text color: White, String: "TOPSECRET//SI/TK/NOFORN                  **G//HCS//NATO SECRET FOR APPROVED USERS IN SELECTED STORAGE SPACE**"

#$SaltStates = "None" #Comma-separated list of salt states. Listed states will be applied to the system. Parameter key:
                      #-- "None"              -- Special keyword; will not apply any salt states
                      #-- "Highstate"         -- Special keyword; applies the salt "highstate" as defined in the SystemPrep top.sls file
                      #-- "user,defined,list" -- User may pass in a comma-separated list of salt states to apply to the system; state names are case-sensitive and must match exactly

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
        New-Item "${SaveTo}" -ItemType "file" -Force > $null
        (new-object net.webclient).DownloadFile("${Url}","${SaveTo}") 2>&1
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
    New-Item -ItemType Directory -Force -Path $DestPath -WarningAction SilentlyContinue > $null
    $Shell.namespace($DestPath).copyhere($Shell.namespace("$SourcePath\$FileName").items(), 0x14) 
}

#Make sure the salt working directories exist
if (-Not (Test-Path $SaltWorkingDir)) { New-Item -Path $SaltWorkingDir -ItemType "directory" -Force > $null; log "Created working directory -- ${SaltWorkingDir}" } else { log "Working directory already exists -- ${SaltWorkingDir}" }

#Create log entry to note the script that is executing
log $ScriptStart
log "Within ${ScriptName} --"
log "SaltWorkingDir = ${SaltWorkingDir}"
log "SaltContentUrl = ${SaltContentUrl}"
log "FormulasToInclude = ${FormulasToInclude}"
log "FormulaTerminationStrings = ${FormulaTerminationStrings}"
log "AshRole = ${AshRole}"
log "NetBannerString = ${NetBannerString}"
log "SaltStates = ${SaltStates}"
log "RemainingArgsHash = $(($RemainingArgsHash.GetEnumerator() | % { `"-{0}: {1}`" -f $_.key, $_.value }) -join ' ')"

#Insert script commands
###
$SaltContentFile = (${SaltContentUrl}.split('/'))[-1]
Download-File -Url $SaltContentUrl -SaveTo "${SaltWorkingDir}\${SaltContentFile}" | log
Expand-ZipFile -FileName ${SaltContentFile} -SourcePath ${SaltWorkingDir} -DestPath ${SaltWorkingDir}

foreach ($Formula in $FormulasToInclude) {
    $FormulaFile = (${Formula}.split('/'))[-1]
    Download-File -Url ${Formula} -SaveTo "${SaltWorkingDir}\${FormulaFile}" | log
    Expand-ZipFile -FileName ${FormulaFile} -SourcePath ${SaltWorkingDir} -DestPath "${SaltWorkingDir}\formulas"
}

#If the formula directory ends in a string in $FormulaTerminationStrings, delete the string from the directory name
$FormulaDirs = @(Get-ChildItem -Path "${SaltWorkingDir}\formulas" | where {$_.Attributes -eq "Directory"})
foreach ($FormulaDir in $FormulaDirs) {
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
if ( ($AshRole -ne "None") -or ($NetBannerString -ne "None") ) {
    $CustomGrainsContent = @()
    $CustomGrainsContent += "grains:"

    if ($AshRole -ne "None") {
        log "Writing the Ash role to a grain in the salt configuration file"
        $AshRoleCustomGrain = @()
        $AshRoleCustomGrain += "  ash-windows:"
        $AshRoleCustomGrain += "    role: ${AshRole}"
    }
    if ($NetBannerString -ne "None") {
        log "Writing the NetBanner string to a grain in the salt configuration file"
        $NetBannerStringCustomGrain = @()
        $NetBannerStringCustomGrain += "  netbanner:"
        $NetBannerStringCustomGrain += "    string: ${NetBannerString}"
    }

    $CustomGrainsContent += $AshRoleCustomGrain
    $CustomGrainsContent += $NetBannerStringCustomGrain
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

log "Restarting salt-minion service"
(Get-Service -name $MinionService) | Stop-Service -PassThru | Start-Service

if ("None" -eq $SaltStates) {
    log "Detected the States parameter is set to: ${SaltStates}. Will not apply any salt states."
} elseif ("Highstate" -eq $SaltStates ) {
    log "Detected the States parameter is set to: ${SaltStates}. Applying the salt `"highstate`" to the system."
    $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.highstate" -NoNewWindow -PassThru -Wait
} else {
    log "Detected the States parameter is set to: ${SaltStates}. Applying the user-defined list of states to the system."
    $ApplyStatesResult = Start-Process $MinionExe -ArgumentList "--local state.sls ${SaltStates}" -NoNewWindow -PassThru -Wait
}
###

#Log exit from script
log "Exiting ${ScriptName} -- salt install complete"
log $ScriptEnd