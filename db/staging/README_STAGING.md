Staging import (bulk)

This folder contains a staging-based import flow designed for large CSV datasets.

Files:
- `mssql_staging_schema.sql` — creates `stg_*` tables and the stored procedure `dbo.ImportFromStaging` which maps staging rows into production tables.
- `staging_import.ps1` — PowerShell script that:
  - Deploys the staging schema/proc to the target database,
  - Uses `BULK INSERT` to load CSV files into the staging tables,
  - Calls `dbo.ImportFromStaging` to map/insert into production tables.

Important notes about file access:
- `BULK INSERT` is executed by the SQL Server service and therefore the CSV files must be accessible from the server machine (local path or network share) and readable by the SQL Server service account.
- If your SQL Server instance is remote and cannot access your local CSV folder, either:
  - Copy the CSV files to a folder on the database server or to a network share the server can access, or
  - Use `bcp` from the client machine to load directly into staging tables, or
  - Use a client-side script that reads CSV rows and performs inserts (slower but does not require server file access).

Minimal example (PowerShell, Windows auth):

```powershell
cd .\golf-stats-app\db
# Ensure the files are reachable by the SQL Server instance (copy to server if needed)
.\staging_import.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -CsvFolder ".\csv_templates"
```

If you need, I can:
- Provide a `bcp`-based client script to load CSVs from your machine into staging tables without copying files to the server, or
- Add a parameter to `staging_import.ps1` that uploads CSVs to a server share before running BULK INSERT (needs credentials/access), or
- Add logging/validation to the stored procedure for per-row errors.
