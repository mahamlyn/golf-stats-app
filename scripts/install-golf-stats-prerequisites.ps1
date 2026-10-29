[CmdletBinding()]
param()

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

function Install-WingetPackage {
    param(
        [string]$PackageId,
        [string]$Component,
        [bool]$AlreadyInstalled
    )

    if ($AlreadyInstalled) {
        Write-Host "$Component is already installed."
        return
    }
    Write-Host "Installing $Component from the winget source..."
    & winget install --id $PackageId --exact --source winget --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install $Component (package '$PackageId') with exit code $LASTEXITCODE."
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
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget is not installed or not on PATH. Install/enable Microsoft App Installer and reopen elevated 64-bit PowerShell.'
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

Write-Host 'Installing missing prerequisites with winget...'
Install-WingetPackage -PackageId 'Python.Python.3.12' -Component 'Python 3.12 x64' -AlreadyInstalled (Test-Python312X64)
Install-WingetPackage -PackageId 'Microsoft.msodbcsql.18' -Component 'Microsoft ODBC Driver 18 x64' -AlreadyInstalled (Test-Odbc18)
Install-WingetPackage -PackageId 'Microsoft.Sqlcmd' -Component 'Microsoft sqlcmd' -AlreadyInstalled ([bool](Get-Command sqlcmd -ErrorAction SilentlyContinue))
Install-WingetPackage -PackageId 'Microsoft.IIS.URLRewrite' -Component 'IIS URL Rewrite' -AlreadyInstalled (Test-IisModule -ModuleName 'RewriteModule')
Install-WingetPackage -PackageId 'Microsoft.IIS.ApplicationRequestRouting' -Component 'IIS Application Request Routing' -AlreadyInstalled (Test-IisModule -ModuleName 'ApplicationRequestRouting')
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
