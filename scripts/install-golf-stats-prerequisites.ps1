[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerDirectory,

    [string]$PythonInstaller,
    [string]$OdbcDriverInstaller,
    [string]$SqlCmdInstaller,
    [string]$UrlRewriteInstaller,
    [string]$ArrInstaller
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Python312X64 {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        return $false
    }

    $output = & py -3.12 -c "import struct,sys; print('%s.%s|%s' % (sys.version_info[0],sys.version_info[1],struct.calcsize('P') * 8))" 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }
    return $output -match '^3\.12\|64$'
}

function Test-Odbc18 {
    return Test-Path 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 18 for SQL Server'
}

function Test-IisModule {
    param([string]$ModuleName)

    if (-not (Get-Module -ListAvailable -Name WebAdministration)) {
        return $false
    }
    Import-Module WebAdministration -ErrorAction Stop
    return (@(Get-WebGlobalModule | ForEach-Object { $_.Name }) -contains $ModuleName)
}

function Resolve-Installer {
    param(
        [string]$FileName,
        [string]$Component,
        [bool]$AlreadyInstalled
    )

    if ($AlreadyInstalled) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        throw "$Component is missing and its installer was not supplied."
    }

    $path = if ([IO.Path]::IsPathRooted($FileName)) {
        $FileName
    } else {
        Join-Path $InstallerDirectory $FileName
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$Component installer not found: $path"
    }
    return (Resolve-Path -LiteralPath $path).Path
}

function Assert-SignedInstaller {
    param(
        [string]$Path,
        [string]$ExpectedPublisher
    )

    if (-not $Path) {
        return
    }
    $signature = Get-AuthenticodeSignature -FilePath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch $ExpectedPublisher) {
        throw "Installer signature validation failed for '$Path'. Expected a valid signature from $ExpectedPublisher."
    }
}

function Install-Msi {
    param(
        [string]$Path,
        [string[]]$Properties = @()
    )

    if (-not $Path) {
        return
    }
    $logPath = Join-Path $env:TEMP ("GolfStats-{0}-{1}.log" -f [IO.Path]::GetFileNameWithoutExtension($Path), [guid]::NewGuid().ToString('N'))
    $arguments = @('/i', ('"{0}"' -f $Path), '/qn', '/norestart', '/L*v', ('"{0}"' -f $logPath)) + $Properties
    $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Installer failed with exit code $($process.ExitCode). See $logPath"
    }
    if ($process.ExitCode -eq 3010) {
        $script:RebootRequired = $true
    }
}

function Install-Executable {
    param(
        [string]$Path,
        [string]$Arguments
    )

    if (-not $Path) {
        return
    }
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Installer '$Path' failed with exit code $($process.ExitCode)."
    }
    if ($process.ExitCode -eq 3010) {
        $script:RebootRequired = $true
    }
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $paths = @($machinePath, $userPath) | Where-Object { $_ }
    $env:Path = $paths -join ';'
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This setup script must run on Windows Server.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Run this script from 64-bit PowerShell so it can validate and configure 64-bit components.'
}
if (-not (Test-Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}
if (-not (Test-Path -LiteralPath $InstallerDirectory -PathType Container)) {
    throw "Installer directory does not exist: $InstallerDirectory"
}
if (-not (Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue)) {
    throw 'Install-WindowsFeature is unavailable. Run this on Windows Server with ServerManager installed.'
}

$RebootRequired = $false
$features = @(
    'Web-Server',
    'Web-Default-Doc',
    'Web-Static-Content',
    'Web-Http-Errors',
    'Web-Http-Logging',
    'Web-Filtering',
    'Web-Windows-Auth',
    'Web-Mgmt-Console',
    'Web-Scripting-Tools'
)
$missingFeatures = @($features | Where-Object { -not (Get-WindowsFeature -Name $_).Installed })

$pythonPath = Resolve-Installer -FileName $PythonInstaller -Component 'Python 3.12 x64' -AlreadyInstalled (Test-Python312X64)
$odbcPath = Resolve-Installer -FileName $OdbcDriverInstaller -Component 'Microsoft ODBC Driver 18 x64' -AlreadyInstalled (Test-Odbc18)
$sqlcmdPath = Resolve-Installer -FileName $SqlCmdInstaller -Component 'Microsoft sqlcmd' -AlreadyInstalled ([bool](Get-Command sqlcmd -ErrorAction SilentlyContinue))
$rewritePath = Resolve-Installer -FileName $UrlRewriteInstaller -Component 'IIS URL Rewrite' -AlreadyInstalled (Test-IisModule -ModuleName 'RewriteModule')
$arrPath = Resolve-Installer -FileName $ArrInstaller -Component 'IIS Application Request Routing' -AlreadyInstalled (Test-IisModule -ModuleName 'ApplicationRequestRouting')

Assert-SignedInstaller -Path $pythonPath -ExpectedPublisher 'Python Software Foundation'
Assert-SignedInstaller -Path $odbcPath -ExpectedPublisher 'Microsoft Corporation'
Assert-SignedInstaller -Path $sqlcmdPath -ExpectedPublisher 'Microsoft Corporation'
Assert-SignedInstaller -Path $rewritePath -ExpectedPublisher 'Microsoft Corporation'
Assert-SignedInstaller -Path $arrPath -ExpectedPublisher 'Microsoft Corporation'

Write-Host 'Installing required Windows Server IIS features...'
if ($missingFeatures.Count -gt 0) {
    $featureResult = Install-WindowsFeature -Name $missingFeatures -IncludeManagementTools
    if (-not $featureResult.Success) {
        throw 'One or more IIS Windows features could not be installed.'
    }
    if ($featureResult.RestartNeeded -eq 'Yes') {
        $RebootRequired = $true
    }
}

Write-Host 'Installing missing signed prerequisites...'
Install-Executable -Path $pythonPath -Arguments '/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1 Include_pip=1'
Install-Msi -Path $odbcPath -Properties @('IACCEPTMSODBCSQLLICENSETERMS=YES')
Install-Msi -Path $sqlcmdPath -Properties @('IACCEPTSQLCMDLICENSETERMS=YES')
Install-Msi -Path $rewritePath
Install-Msi -Path $arrPath
Refresh-ProcessPath

Import-Module WebAdministration -ErrorAction Stop
if (-not (Test-IisModule -ModuleName 'RewriteModule')) {
    throw 'IIS URL Rewrite did not register its IIS module.'
}
if (-not (Test-IisModule -ModuleName 'ApplicationRequestRouting')) {
    throw 'IIS ARR did not register its IIS module.'
}
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/proxy' -Name enabled -Value $true

if (-not (Test-Python312X64)) {
    throw 'Python 3.12 x64 was not detected after installation. Reopen PowerShell or reboot, then run this script again.'
}
if (-not (Test-Odbc18)) {
    throw 'The 64-bit ODBC Driver 18 was not detected after installation.'
}
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'sqlcmd was not detected on PATH after installation. Reopen PowerShell or reboot, then run this script again.'
}

Write-Host 'Golf Stats server prerequisites are installed and ARR proxying is enabled.'
if ($RebootRequired) {
    Write-Warning 'A prerequisite requested a reboot. Reboot the server before configuring the site or running the deployment workflow.'
}
Write-Host 'This script does not install SQL Server, create the IIS site or TLS binding, configure a Waitress service, or register the GitHub Actions runner.'
