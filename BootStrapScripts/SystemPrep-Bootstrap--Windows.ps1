[CmdLetBinding()]
Param(
    [String]$SystemPrepMasterScriptUrl = 'https://s3.amazonaws.com/systemprep/MasterScripts/SystemPrep-WindowsMaster.ps1'
    ,    
    [Bool]$NoReboot = $false
    ,
    [String]$SaltStates = 'Highstate'
    ,
    [ValidateSet('Workstation','MemberServer','DomainController')]
    [String]$AshRole = 'MemberServer'
    ,
    [String]$NetBannerLabel = 'Unclass'
    ,
    [Bool]$SourceIsS3Bucket = $false
    ,
    [String]$AwsRegion = 'us-east-1'
    ,
    [String]$RootCertUrl
    ,
    [Bool]$ConfigureEc2EventLogging = $true
)

###
#Define System variables
###
$SystemPrepParams = @{
    AshRole = $AshRole
    NetBannerLabel = $NetBannerLabel
    SaltStates = $SaltStates
    NoReboot = $NoReboot
    SourceIsS3Bucket = $SourceIsS3Bucket
    AwsRegion = $AwsRegion
}
$CertDir = "${env:temp}\certs"
$SystemPrepDir = "${env:SystemDrive}\SystemPrep"
$SystemPrepLogDir = "${env:SystemDrive}\SystemPrep\Logs"
$LogSource = "SystemPrep"
$DateTime = $(get-date -format "yyyyMMdd_HHmm_ss")
$SystemPrepLogFile = "${SystemPrepLogDir}\systemprep-log_${DateTime}.txt"
$ScriptName = $MyInvocation.mycommand.name
$ErrorActionPreference = "Stop"

###
#Define Functions
###
function log {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false,Position=0,ValueFromPipeLine=$true)] [string[]]
        $LogMessage,
        [Parameter(Mandatory=$false,Position=1)] [string]
        $EntryType="Information",
        [Parameter(Mandatory=$false,Position=2)] [string]
        $LogTag="${ScriptName}"
    )
    PROCESS {
        foreach ($message in $LogMessage) {
            $date = get-date -format "yyyyMMdd.HHmm.ss"
            Manage-Output -EntryType $EntryType "${date}: ${LogTag}: $message"
        }
    }
}

function die($Msg) {
    log -EntryType "Error" -LogMessage $Msg
    Stop-Transcript
    throw
}

function Manage-Output {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$false,Position=0,ValueFromPipeLine=$true)] [string[]]
        $Output,
        [Parameter(Mandatory=$false,Position=1)] [string]
        $EntryType="Information"
    )
	PROCESS {
		foreach ($str in $Output) {
            #Write to the event log
            Write-EventLog -LogName Application -Source SystemPrep -EventId 1 -EntryType $EntryType -Message "${str}"
            #Write to the default stream (this way we don't clobber the output stream, and the output will be captured by Start-Transcript)
            "${str}" | Out-Default
		}
	}
}


function Set-RegistryValue($Key,$Name,$Value,$Type=[Microsoft.win32.registryvaluekind]::DWord) {
    $Parent=split-path $Key -parent
    $Parent=get-item $Parent
    $Key=get-item $Key
    $Keyh=$Parent.opensubkey($Key.name.split("\")[-1],$true)
    $Keyh.setvalue($Name,$Value,$Type)
    $Keyh.close()
}


function Set-OutputBuffer($Width=10000) {
    $keys=("hkcu:\console\%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe",
           "hkcu:\console\%SystemRoot%_SysWOW64_WindowsPowerShell_v1.0_powershell.exe")
    # other titles are ignored
    foreach ($key in $keys) {
        if (!(test-path $key)) {md $key -verbose}
        Set-RegistryValue $key FontSize 0x00050000
        Set-RegistryValue $key ScreenBufferSize 0x02000200
        Set-RegistryValue $key WindowSize 0x00200200
        Set-RegistryValue $key FontFamily 0x00000036
        Set-RegistryValue $key FontWeight 0x00000190
        Set-ItemProperty $key FaceName "Lucida Console"

        $bufferSize=$host.ui.rawui.bufferSize
        $bufferSize.width=$Width
        $host.ui.rawui.BufferSize=$BufferSize
        $maxSize=$host.ui.rawui.MaxWindowSize
        $windowSize=$host.ui.rawui.WindowSize
        $windowSize.width=$maxSize.width
        $host.ui.rawui.WindowSize=$windowSize
    }
}


function Download-File {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true)] [string[]] $Url,
        [Parameter(Mandatory=$true,Position=1)] [string] $SavePath,
        [Parameter(Mandatory=$false,Position=2)] [switch] $SourceIsS3Bucket,
        [Parameter(Mandatory=$false,Position=3)] [string] $AwsRegion
    )
    BEGIN {
        New-Item -Path ${SavePath} -ItemType Directory -Force -WarningAction SilentlyContinue > $null
    }
    PROCESS {
        foreach ($url_item in $Url) {
            $FileName = "${SavePath}\$((${url_item}.split('/'))[-1])"
            if ($SourceIsS3Bucket) {
                log "Downloading file from S3 bucket: ${url_item}"
                $SplitUrl = $url_item.split('/') | where { $_ -notlike "" }
                $BucketName = $SplitUrl[2]
                $Key = $SplitUrl[3..($SplitUrl.count-1)] -join '/'
                $ret = Invoke-Expression "Powershell Read-S3Object -BucketName $BucketName -Key $Key -File $FileName -Region $AwsRegion"
            }
            else {
                log "Downloading file from HTTP host: ${url_item}"
                (new-object net.webclient).DownloadFile("${url_item}","${FileName}")
            }
            Write-Output (Get-Item $FileName)
        }
    }
}


function Expand-ZipFile {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true)] [string[]] $FileName,
        [Parameter(Mandatory=$true,Position=1)] [string] $DestPath,
        [Parameter(Mandatory=$false,Position=2)] [switch] $CreateDirFromFileName
    )
    PROCESS {
        foreach ($file in $FileName) {
            if (!(Test-Path "$file")) {
                throw "$file does not exist"
            }
            log "Unzipping file: ${file}"
            if ($CreateDirFromFileName) { $DestPath = "${DestPath}\$((Get-Item $file).BaseName)" }
            $null = New-Item -Path $DestPath -ItemType Directory -Force -WarningAction SilentlyContinue
            new-object -com shell.application | % {
                $_.namespace($DestPath).copyhere($_.namespace("$file").items(), 0x14) 
            }
            Write-Output (Get-Item $DestPath)
        }
    }
}


function Import-509Certificate {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true)] [string[]] $certPath,
        [Parameter(Mandatory=$true,Position=1)] [string] $certRootStore,
        [Parameter(Mandatory=$true,Position=2)] [string] $certStore
    )
    PROCESS {
        foreach ($item in $certpath) {
            log "Importing certificate: ${item}"
            $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2
            $pfx.import($item)

            $store = new-object System.Security.Cryptography.X509Certificates.x509Store($certStore,$certRootStore)
            $store.open("MaxAllowed")
            $store.add($pfx)
            $store.close()
        }
    }
}


function Install-RootCerts {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true)] [string[]] $RootCertHost
    )
    PROCESS {
        foreach ($item in $RootCertHost) {
            $CertDir = "${env:temp}\certs-$(${item}.Replace(`"http://`",`"`"))"
            New-Item -Path $CertDir -ItemType "directory" -Force -WarningAction SilentlyContinue > $null
            log "...Checking for certificates hosted by: $item..."
            $CertUrls = @((Invoke-WebRequest -Uri $item).Links | where { $_.href -match ".*\.cer$"} | foreach-object {$item + $_.href})
            log "...Found $(${CertUrls}.count) certificate(s)..."
            log "...Downloading certificate(s)..."
            $CertFiles = $CertUrls | Download-File -SavePath $CertDir
            $TrustedRootCACertFiles = $CertFiles | where { $_.Name -match ".*root.*" }
            $IntermediateCACertFiles = $CertFiles | where { $_.Name -notmatch ".*root.*" }
            log "...Beginning import of $(${TrustedRootCACertFiles}.count) trusted root CA certificate(s)..."
            $TrustedRootCACertFiles | Import-509Certificate -certRootStore "LocalMachine" -certStore "Root"
            log "...Beginning import of $(${IntermediateCACertFiles}.count) intermediate CA certificate(s)..."
            $IntermediateCACertFiles | Import-509Certificate -certRootStore "LocalMachine" -certStore "CA"
            log "...Completed import of certificate(s) from: ${item}"
        }
    }
}


function Enable-Ec2EventLogging {
    [CmdLetBinding()]
    Param()
    PROCESS {
        $EC2SettingsFile = "${env:ProgramFiles}\Amazon\Ec2ConfigService\Settings\Config.xml"
        $xml = [xml](get-content $EC2SettingsFile)
        $xmlElement = $xml.get_DocumentElement()
        $xmlElementToModify = $xmlElement.Plugins

        foreach ($element in $xmlElementToModify.Plugin) {
            if ($element.name -eq "Ec2EventLog") {
                $element.State = "Enabled"
            }
        }
        $xml.Save($EC2SettingsFile)
        log "Enabled EC2 event logging"
    }
}


function Add-Ec2EventLogSource {
    [CmdLetBinding()]
    Param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$false)] [string[]] $LogSource
    )
    PROCESS {
        foreach ($Source in $LogSource) {
            $EC2EventLogFile = "${env:ProgramFiles}\Amazon\Ec2ConfigService\Settings\EventLogConfig.xml"
            $xml = [xml](Get-Content $EC2EventLogFile)

            foreach ($MessageType in @("Information","Warning","Error")) {
                $xmlElement = $xml.EventLogConfig.AppendChild($xml.CreateElement("Event"))

                $xml_category = $xmlElement.AppendChild($xml.CreateElement("Category"))
                $xml_category.AppendChild($xml.CreateTextNode("Application")) | Out-null

                $xml_errortype = $xmlElement.AppendChild($xml.CreateElement("ErrorType"))
                $xml_errortype.AppendChild($xml.CreateTextNode($MessageType)) | Out-null

                $xml_numentries = $xmlElement.AppendChild($xml.CreateElement("NumEntries"))
                $xml_numentries.AppendChild($xml.CreateTextNode("9999")) | Out-null

                $xml_appname = $xmlElement.AppendChild($xml.CreateElement("AppName"))
                $xml_appname.AppendChild($xml.CreateTextNode("${Source}")) | Out-null

                $xml_lastmessagetime = $xmlElement.AppendChild($xml.CreateElement("LastMessageTime"))
                $xml_lastmessagetime.AppendChild($xml.CreateTextNode($(get-date -Format "yyyy-MM-ddTHH:mm:ss.0000000+00:00"))) | Out-null
            }

            $xml.Save($EC2EventLogFile)
            log "Added the log source, ${Source}, to the EC2 Event Log configuration file"
        }
    }
}


###
#Begin Script
###

#Create the SystemPrep log directory
New-Item -Path $SystemPrepDir -ItemType "directory" -Force 2>&1 > $null
New-Item -Path $SystemPrepLogDir -ItemType "directory" -Force 2>&1 > $null
#Increase the screen width to avoid line wraps in the log file
Set-OutputBuffer -Width 10000
#Start a transcript to record script output
Start-Transcript $SystemPrepLogFile

#Create a "SystemPrep" event log source
try {
    New-EventLog -LogName Application -Source "${LogSource}"
} catch {
    if ($_.Exception.GetType().FullName -eq "System.InvalidOperationException") {
        # Event log already exists, log a message but don't force an exit
        log "Event log source, ${LogSource}, already exists. Continuing..."
    } else {
        # Unhandled exception, log an error and exit!
        "$(get-date -format "yyyyMMdd.HHmm.ss"): ${ScriptName}: ERROR: Encountered a problem creating the event log source." | Out-Default
        Stop-Transcript
        throw
    }
}

if ($ConfigureEc2EventLogging) {
    #Enable and configure EC2 event logging
    try {
        Enable-Ec2EventLogging
        Add-Ec2EventLogSource -LogSource ${LogSource}
    } catch {
        # Unhandled exception, log an error and exit!
        die "ERROR: Encountered a problem configuring EC2 event logging."
    }
}

if ($RootCertUrl) {
    #Download and install the root certificates
    try {
        Install-RootCerts -RootCertHost ${RootCertUrl}
    } catch {
        # Unhandled exception, log an error and exit!
        die "ERROR: Encountered a problem installing root certificates."
    }
}

#Download the master script
log "Downloading the SystemPrep master script: ${SystemPrepMasterScriptUrl}"
try {
    $SystemPrepMasterScript = Download-File $SystemPrepMasterScriptUrl $SystemPrepDir -SourceIsS3Bucket:($SystemPrepParams["SourceIsS3Bucket"]) -AwsRegion $SystemPrepParams["AwsRegion"]
} catch {
    # Unhandled exception, log an error and exit!
    die "ERROR: Encountered a problem downloading the master script!"
}

#Execute the master script
log "Running the SystemPrep master script: ${SystemPrepMasterScript}"
try {
    Invoke-Expression "& ${SystemPrepMasterScript} @SystemPrepParams" | Manage-Output
} catch {
    # Unhandled exception, log an error and exit!
    die "ERROR: Encountered a problem executing the master script!"
}

#Reached the exit without an error, log success message
log "SystemPrep completed successfully! Exiting..."
Stop-Transcript
