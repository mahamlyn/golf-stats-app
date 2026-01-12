<#
PowerShell script to bulk-load CSV files into staging tables on SQL Server, then run the T-SQL mapping procedure `dbo.ImportFromStaging`.

Notes and requirements:
- BULK INSERT runs on the SQL Server service account. The CSV files must be accessible from the server machine (local path or UNC) and readable by the SQL Server process.
- If SQL Server cannot access those files, use `bcp` from the client machine (not implemented here) or copy the CSVs to a server-accessible share.
- The script will create staging tables and the import procedure if they don't exist by executing `mssql_staging_schema.sql` in the target database.

Usage (PowerShell):
cd <repo>\golf-stats-app\db
# Windows auth
.\staging_import.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -CsvFolder ".\csv_templates"

# SQL auth
.\staging_import.ps1 -ServerInstance "localhost,1433" -DatabaseName "GolfStats" -CsvFolder ".\csv_templates" -Username "sa" -Password "P@ssw0rd"
#>

[CmdletBinding()]
param(
    [string]$ServerInstance = 'localhost',
    [string]$DatabaseName = 'GolfStats',
    [string]$CsvFolder = (Join-Path $PSScriptRoot '..\csv_templates'),
    [string]$SchemaScript = (Join-Path $PSScriptRoot 'mssql_staging_schema.sql'),
    [string]$Username,
    [string]$Password
)

function Ensure-Module { param([string]$Name) if (-not (Get-Module -ListAvailable -Name $Name)) { Install-Module -Name $Name -Scope CurrentUser -Force } }
Ensure-Module -Name 'SqlServer'

if (-not (Test-Path $CsvFolder)) { Write-Error "CSV folder not found: $CsvFolder"; exit 1 }
if (-not (Test-Path $SchemaScript)) { Write-Error "Schema script not found: $SchemaScript"; exit 1 }

# Helper to run Invoke-Sqlcmd with optional SQL auth
function Invoke-Sql { param($Server,$Database,$Query) $p = @{ ServerInstance = $Server; Query = $Query } ; if ($Database) { $p['Database'] = $Database }; if ($PSBoundParameters.ContainsKey('Username') -and $Username) { $p['Username'] = $Username; $p['Password'] = $Password } ; Invoke-Sqlcmd @p }

# Deploy staging schema and procedure
Write-Host "Deploying staging schema/proc to [$DatabaseName] on $ServerInstance"
Invoke-Sql -Server $ServerInstance -Database $DatabaseName -Query (Get-Content $SchemaScript -Raw)

# Helper for BULK INSERT. Note: path must be accessible from SQL Server service.
function Bulk-Insert-Table {
    param(
        [string]$TargetTable,
        [string]$CsvPath
    )
    $full = Resolve-Path $CsvPath
    $serverPath = $full.Path

    # Use SQL Server BULK INSERT. FIRSTROW=2 to skip header.
    $bulq = @"
BULK INSERT $TargetTable
FROM N'$serverPath'
WITH (
  FIRSTROW = 2,
  FIELDTERMINATOR = ',',
  ROWTERMINATOR = '0x0a',
  CODEPAGE = '65001',
  TABLOCK
);
"@
    Write-Host "Attempting BULK INSERT into $TargetTable from $serverPath"
    try {
        Invoke-Sql -Server $ServerInstance -Database $DatabaseName -Query $bulq
    }
    catch {
        Write-Warning "BULK INSERT failed for $CsvPath: $_"
        throw
    }
}

try {
    # Files (server must be able to access these paths)
    $membersCsv = Join-Path $CsvFolder 'members.csv'
    $coursesCsv = Join-Path $CsvFolder 'courses.csv'
    $roundsCsv  = Join-Path $CsvFolder 'rounds.csv'
    $holesCsv   = Join-Path $CsvFolder 'holes.csv'

    if (-not (Test-Path $membersCsv)) { Write-Warning "Missing $membersCsv" }
    if (-not (Test-Path $coursesCsv)) { Write-Warning "Missing $coursesCsv" }
    if (-not (Test-Path $roundsCsv))  { Write-Warning "Missing $roundsCsv" }
    if (-not (Test-Path $holesCsv))   { Write-Warning "Missing $holesCsv" }

    # Bulk insert into staging tables
    Bulk-Insert-Table -TargetTable 'dbo.stg_members' -CsvPath $membersCsv
    Bulk-Insert-Table -TargetTable 'dbo.stg_courses' -CsvPath $coursesCsv
    Bulk-Insert-Table -TargetTable 'dbo.stg_rounds'  -CsvPath $roundsCsv
    Bulk-Insert-Table -TargetTable 'dbo.stg_holes'   -CsvPath $holesCsv

    Write-Host "Bulk insert complete. Executing dbo.ImportFromStaging..."

    Invoke-Sql -Server $ServerInstance -Database $DatabaseName -Query "EXEC dbo.ImportFromStaging;"

    Write-Host "ImportFromStaging executed successfully."
}
catch {
    Write-Error "Error during staging import: $_"
    exit 1
}

Write-Host "Done. If necessary, manually truncate staging tables or modify the stored procedure to clear them." 