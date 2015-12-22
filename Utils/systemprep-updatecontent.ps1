[CmdLetBinding()]
Param(
    [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
    $Environment
    ,
    [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$false)]
    [ValidateSet('None','Workstation','MemberServer','DomainController')]
    [String] $SystemRole
    ,
    [Parameter(Mandatory=$false, ValueFromPipeline=$false)]
    [String] $BootstrapUrl = 'https://s3.amazonaws.com/systemprep/BootStrapScripts/SystemPrep-Bootstrap--Windows.ps1'
)

BEGIN
{
    $ScriptName = $MyInvocation.mycommand.name

    function Download-File
    {
        [CmdLetBinding()]
        Param(
            [Parameter(Mandatory=$true,Position=0,ValueFromPipeLine=$true)]
            [ValidateScript({ $_ -match "^http[s]?://" })]
            [string[]] $Url
            ,
            [Parameter(Mandatory=$true,Position=1)]
            [string] $SaveTo
        )
        BEGIN
        {
            $FunctionName = $MyInvocation.MyCommand.Name
            $null = New-Item -Path "${SaveTo}" -ItemType Directory -Force `
                -WarningAction SilentlyContinue
        }
        PROCESS
        {
            foreach ($Item in $Url) {
                $FileName = Join-Path -Path "${SaveTo}" -ChildPath ${Item}.split('/')[-1]
                Write-Verbose "${FunctionName}: Source: ${Item}"
                Write-Verbose "${FunctionName}: Destination: ${FileName}"
                (new-object net.webclient).DownloadFile("${Item}","${FileName}")
                Get-Item $FileName
            }
        }
    }


    function New-TempDir
    {
        [CmdLetBinding()]
        Param(
            [Parameter(Mandatory=$false)]
            [string] $PrependString
        )
        BEGIN
        {
            $FunctionName = $MyInvocation.MyCommand.Name
        }
        END
        {
            $TempDir = Join-Path `
                -Path ([System.IO.Path]::GetTempPath()) `
                -ChildPath ( [string]::join( `
                    "${PrependString}", `
                    [System.IO.Path]::GetRandomFileName() `
                ) )
            Write-Verbose "${FunctionName}: Creating directory: ${TempDir}"
            New-Item -Path "${TempDir}" -ItemType Directory
        }
    }
}

END
{
    # Create temp dir
    $TempDir = New-TempDir

    # Download the bootstrapper
    $BootstrapFile = Download-File -Url "${BootstrapUrl}" -SaveTo "${TempDir}"

    # Create hash table of parameters to pass to the bootstrapper
    $BootstrapParams = @{
        AshRole = "${SystemRole}"
        EntEnv = "${Environment}"
        SaltStates = "None"
        NoReboot = $true
    }

    # Execute
    Write-Verbose "Using bootstrapper to update systemprep content..."
    try
    {
        Invoke-Expression "& ${BootstrapFile} @BootstrapParams"
    }
    catch
    {
        # Unhandled exception, log an error and exit!
        throw "Encountered a problem executing the bootstrapper!"
    }

    # Success
    Write-Verbose "Successfully updated systemprep content."

    # Cleanup
    Remove-Item $TempDir -Recurse -Force
}
