MS-SQL deployment

This file describes how to create a SQL Server database and deploy the schema using the provided PowerShell script.

Prerequisites:
- Windows PowerShell (or PowerShell Core) on Windows.
- The `SqlServer` PowerShell module (the script will attempt to install it into the current user scope if missing).
- Permission to create/drop databases on the target SQL Server instance.

Files:
- `mssql_schema.sql` - T-SQL schema compatible with SQL Server.
- `create_db.ps1` - PowerShell script to create the database and run the schema.

Examples (PowerShell):

# Create DB using Windows Authentication
```powershell
cd .\golf-stats-app\db\mssql
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql"
```

# Create DB using SQL Authentication
```powershell
.\create_db.ps1 -ServerInstance "my.server.com,1433" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql" -Username "sa" -Password "P@ssw0rd"
```

# Force recreate DB
```powershell
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql" -Force
```

Notes:
- If you prefer `sqlcmd.exe`, you can run `sqlcmd -S <server> -i mssql_schema.sql` after creating the database.
- For production setups, use secure credential handling (Windows Auth or secure secrets manager) rather than plain-text passwords.
