<#
PowerShell script to create a SQL Server database and deploy the T-SQL schema.

Usage examples (PowerShell):

# Create DB using Windows Authentication
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql"

# Create DB using SQL authentication
.\create_db.ps1 -ServerInstance "localhost,1433" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql" -Username "sa" -Password "P@ssw0rd"

# Force recreate DB
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql" -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ServerInstance = 'localhost',

    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = 'GolfStats',

    [Parameter(Mandatory=$false)]
    [string]$SchemaPath = (Join-Path $PSScriptRoot 'mssql_schema.sql'),

    [Parameter(Mandatory=$false)]
    [switch]$Force,

    [Parameter(Mandatory=$false)]
    [string]$Username,

    [Parameter(Mandatory=$false)]
    [string]$Password
)

function Ensure-Module {
    param([string]$Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Module '$Name' not found. Installing to CurrentUser..."
        try {
            Install-Module -Name $Name -Scope CurrentUser -Force -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to install module '$Name'. Run PowerShell as admin or install the SqlServer module manually. Error: $_"
            throw
        }
    }
}

Write-Host "Using server: $ServerInstance`nDatabase: $DatabaseName`nSchema: $SchemaPath"

if (-not (Test-Path $SchemaPath)) {
    Write-Error "Schema file not found: $SchemaPath"
    exit 1
}

Ensure-Module -Name 'SqlServer'

# helper to run Invoke-Sqlcmd with either Windows auth (no creds) or SQL auth
function Invoke-Sql {
    param(
        [string]$Server,
        [string]$Database,
        [string]$Query,
        [string]$InputFile
    )
    $params = @{ ServerInstance = $Server }
    if ($PSBoundParameters.ContainsKey('Username') -and $Username) {
        $params['Username'] = $Username
        $params['Password'] = $Password
    }
    if ($Database) { $params['Database'] = $Database }
    if ($InputFile) { $params['InputFile'] = $InputFile }
    else { $params['Query'] = $Query }

    return Invoke-Sqlcmd @params
}

try {
    # Check if database exists
    $exists = Invoke-Sql -Server $ServerInstance -Database 'master' -Query "SELECT database_id FROM sys.databases WHERE name = N'$DatabaseName';"
    if ($exists) {
        if ($Force) {
            Write-Host "Database exists. Dropping (force)..."
            # Set SINGLE_USER and drop to ensure we can remove it
            Invoke-Sql -Server $ServerInstance -Database 'master' -Query "ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$DatabaseName];"
            Write-Host "Dropped database $DatabaseName"
        }
        else {
            Write-Host "Database '$DatabaseName' already exists. Use -Force to recreate or choose a different name."
            exit 0
        }
    }

    Write-Host "Creating database '$DatabaseName'..."
    Invoke-Sql -Server $ServerInstance -Database 'master' -Query "CREATE DATABASE [$DatabaseName];"
    Write-Host "Database created. Deploying schema..."

    # Deploy schema file
    Invoke-Sql -Server $ServerInstance -Database $DatabaseName -InputFile $SchemaPath

    Write-Host "Schema deployed successfully to database: $DatabaseName"
}
catch {
    Write-Error "Error while creating/deploying database: $_"
    exit 1
}
