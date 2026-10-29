$ErrorActionPreference = 'Stop'

function Require-Setting {
    param([string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Required GitHub Environment variable '$Name' is not configured."
    }
    return $value
}

function Invoke-SqlCmd {
    param(
        [string]$Database,
        [string]$InputFile,
        [string]$Query
    )

    $sqlcmdArgs = @('-S', $sqlServer, '-d', $Database, '-E', '-b')
    if ($trustServerCertificate) {
        $sqlcmdArgs += '-C'
    }
    if ($InputFile) {
        $sqlcmdArgs += @('-i', $InputFile)
    } else {
        $sqlcmdArgs += @('-h', '-1', '-W', '-Q', $Query)
    }

    $output = & sqlcmd @sqlcmdArgs
    if ($LASTEXITCODE -ne 0) {
        throw "sqlcmd failed for database '$Database' with exit code $LASTEXITCODE. $($output -join ' ')"
    }
    return $output
}

$deployRoot = [IO.Path]::GetFullPath((Require-Setting 'GOLF_DEPLOY_ROOT'))
$serviceName = Require-Setting 'GOLF_SERVICE_NAME'
$iisSiteName = Require-Setting 'GOLF_IIS_SITE_NAME'
$healthUrl = Require-Setting 'GOLF_HEALTH_URL'
$sqlServer = Require-Setting 'GOLF_SQL_SERVER'
$seedSampleData = $env:GOLF_SEED_SAMPLE_DATA -eq 'true'
$trustServerCertificate = $env:GOLF_TRUST_SERVER_CERTIFICATE -eq 'true'
$databaseName = 'GolfStats'

if ($serviceName -notmatch '^[A-Za-z0-9_.-]+$') {
    throw 'GOLF_SERVICE_NAME contains unsupported characters.'
}
if ($sqlServer -notmatch '^[A-Za-z0-9_.\\,-]+$') {
    throw 'SQL server must be a server or instance name, such as .\SQLEXPRESS or dbhost,1433.'
}
if ($healthUrl -notmatch '^https://') {
    throw 'GOLF_HEALTH_URL must use HTTPS.'
}
if ($deployRoot -match '^[A-Za-z]:\\?$' -or $deployRoot.StartsWith($env:GITHUB_WORKSPACE, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'GOLF_DEPLOY_ROOT must be a dedicated application directory outside the checkout and drive root.'
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'The self-hosted runner must run with administrator rights to deploy files and restart the Windows service.'
}

Write-Host 'Validating deployment prerequisites...'
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw 'Python Launcher (py.exe) is not installed or not on PATH.'
}
$pythonInfo = & py -3.12 -c "import json,struct,sys; print(json.dumps({'version': list(sys.version_info[:2]), 'bits': struct.calcsize('P') * 8}))"
if ($LASTEXITCODE -ne 0) {
    throw 'Python 3.12 is not available through the Python Launcher.'
}
$pythonInfo = $pythonInfo | ConvertFrom-Json
if ($pythonInfo.bits -ne 64) {
    throw 'A 64-bit Python 3.12 installation is required.'
}

$odbcDriverKey = 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 18 for SQL Server'
if (-not (Test-Path $odbcDriverKey)) {
    throw 'The 64-bit Microsoft ODBC Driver 18 for SQL Server is not installed.'
}
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw 'sqlcmd is not installed or not on PATH.'
}
if (-not (Test-Path (Join-Path $env:GITHUB_WORKSPACE 'database\01_create_schema.sql'))) {
    throw 'The SQL schema script is missing from the checked-out repository.'
}

if (-not (Get-Service W3SVC -ErrorAction SilentlyContinue)) {
    throw 'The IIS web service (W3SVC) is not installed.'
}
Import-Module WebAdministration -ErrorAction Stop
$site = Get-Website -Name $iisSiteName -ErrorAction SilentlyContinue
if (-not $site) {
    throw "IIS site '$iisSiteName' does not exist. Provision the site before deploying."
}
if (-not ($site.Bindings.Collection | Where-Object { $_.protocol -eq 'https' })) {
    throw "IIS site '$iisSiteName' has no HTTPS binding."
}
$globalModules = @(Get-WebGlobalModule | ForEach-Object { $_.Name })
if ($globalModules -notcontains 'RewriteModule') {
    throw 'IIS URL Rewrite is not installed.'
}
if ($globalModules -notcontains 'ApplicationRequestRouting') {
    throw 'IIS Application Request Routing (ARR) is not installed.'
}
$proxyEnabled = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.webServer/proxy' -Name enabled
if ($proxyEnabled.Value -ne $true) {
    throw 'IIS ARR proxying is not enabled.'
}
$sitePath = "MACHINE/WEBROOT/APPHOST/$iisSiteName"
$anonymousEnabled = Get-WebConfigurationProperty -PSPath $sitePath -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name enabled
$windowsAuthEnabled = Get-WebConfigurationProperty -PSPath $sitePath -Filter 'system.webServer/security/authentication/windowsAuthentication' -Name enabled
if ($anonymousEnabled.Value -ne $false -or $windowsAuthEnabled.Value -ne $true) {
    throw "IIS site '$iisSiteName' must disable Anonymous Authentication and enable Windows Authentication."
}

$service = Get-CimInstance Win32_Service -Filter "Name='$serviceName'" -ErrorAction SilentlyContinue
if (-not $service) {
    throw "Windows service '$serviceName' does not exist. Provision it to run Waitress from the deployment directory first."
}
if ($service.StartMode -eq 'Disabled') {
    throw "Windows service '$serviceName' is disabled."
}
if ($service.StartMode -ne 'Auto') {
    throw "Windows service '$serviceName' must be configured for automatic startup."
}
if ($service.StartName -match '^(LocalSystem|NT AUTHORITY\\(LocalService|NetworkService))$') {
    throw "Windows service '$serviceName' must use a dedicated service identity, not a built-in account."
}

if (-not (Test-Path $deployRoot)) {
    $parent = Split-Path -Parent $deployRoot
    if (-not (Test-Path $parent)) {
        throw "Deployment parent directory '$parent' does not exist. Create it before deployment."
    }
}
$sqlProbe = "SET NOCOUNT ON; SELECT CONVERT(varchar(30), SERVERPROPERTY('ProductVersion')) + '|' + CONVERT(varchar(128), SERVERPROPERTY('Edition'));"
$sqlInfoLines = Invoke-SqlCmd -Database 'master' -Query $sqlProbe
$sqlInfo = @($sqlInfoLines | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+\.\d+\|' }) | Select-Object -First 1
if (-not $sqlInfo) {
    throw 'Could not read the SQL Server version and edition using the runner identity.'
}
$sqlInfoParts = $sqlInfo -split '\|', 2
$sqlProductVersion = [version]$sqlInfoParts[0]
if ($sqlProductVersion -lt [version]'13.0.4001.0') {
    throw 'SQL Server 2016 SP1 or later is required for CREATE OR ALTER statements.'
}
if ($sqlInfoParts[1] -notmatch 'Express') {
    throw "The target is not SQL Server Express: $($sqlInfoParts[1])."
}

Write-Host "Preflight passed: Python $($pythonInfo.version -join '.') x64, ODBC Driver 18, IIS site '$iisSiteName', service '$serviceName', SQL Server $($sqlInfoParts[0]) Express."
Write-Host 'Applying the idempotent database schema...'
$schemaFile = Join-Path $env:GITHUB_WORKSPACE 'database\01_create_schema.sql'
Invoke-SqlCmd -Database 'master' -InputFile $schemaFile | Out-Null
if ($seedSampleData) {
    Write-Host 'Applying sample data because the manual workflow input was enabled...'
    $seedFile = Join-Path $env:GITHUB_WORKSPACE 'database\02_seed_sample_data.sql'
    Invoke-SqlCmd -Database 'master' -InputFile $seedFile | Out-Null
}

$websiteSource = Join-Path $env:GITHUB_WORKSPACE 'website'
$websiteTarget = Join-Path $deployRoot 'website'
if (-not (Test-Path $deployRoot)) {
    New-Item -ItemType Directory -Path $deployRoot | Out-Null
}
if (-not (Test-Path $websiteTarget)) {
    New-Item -ItemType Directory -Path $websiteTarget | Out-Null
}

$wasRunning = $service.State -eq 'Running'
try {
    if ($wasRunning) {
        Stop-Service -Name $serviceName -Force
        (Get-Service -Name $serviceName).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
    }

    Get-ChildItem -LiteralPath $websiteSource -Force |
        Where-Object { $_.Name -notin @('.gitignore', 'config.json', '.venv', '__pycache__') } |
        Copy-Item -Destination $websiteTarget -Recurse -Force

    & icacls $websiteTarget /grant:r "$($service.StartName):(OI)(CI)(RX)" /T | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not grant the service identity read access to '$websiteTarget'."
    }

    $config = [ordered]@{
        server = $sqlServer
        database = $databaseName
        driver = 'ODBC Driver 18 for SQL Server'
        auth = 'windows'
        username = ''
        password = ''
        trust_server_certificate = $trustServerCertificate
    }
    $configPath = Join-Path $websiteTarget 'config.json'
    $configJson = $config | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($configPath, $configJson, [Text.UTF8Encoding]::new($false))
    & icacls $configPath /grant:r "$($service.StartName):(M)" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Could not grant the service identity access to '$configPath'."
    }

    $venvPython = Join-Path $websiteTarget '.venv\Scripts\python.exe'
    if (-not (Test-Path $venvPython)) {
        & py -3.12 -m venv (Join-Path $websiteTarget '.venv')
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not create the application Python virtual environment.'
        }
    }
    & $venvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not upgrade pip in the application virtual environment.'
    }
    & $venvPython -m pip install -r (Join-Path $websiteTarget 'requirements.txt')
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not install application requirements.'
    }

    Start-Service -Name $serviceName
    (Get-Service -Name $serviceName).WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
    $response = Invoke-WebRequest -Uri $healthUrl -UseDefaultCredentials -TimeoutSec 30
    $health = $response.Content | ConvertFrom-Json
    if ($response.StatusCode -ne 200 -or $health.database.Name -ne $databaseName -or $health.server.Edition -notmatch 'Express') {
        throw 'Post-deployment health check did not report the expected GolfStats database on SQL Server Express.'
    }
} catch {
    $currentService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($wasRunning -and $currentService -and $currentService.Status -ne 'Running') {
        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
    }
    throw
}

Write-Host "Deployment succeeded. Health check passed at $healthUrl"
