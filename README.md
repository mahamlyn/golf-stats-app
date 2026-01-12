## Golf Stats App

**Purpose:** This folder contains the golf-stats application utilities: database schemas, import tooling, and CSV templates used to manage golf scores and related data for family members.

**Contents:**
- **`db/`**: Database artifacts and tooling.
	- **`sqlite/`**: SQLite schema and initializer (`schema.sql`, `init_db.py`) — quick local/dev setup.
	- **`mssql/`**: SQL Server schema and creation script (`mssql_schema.sql`, `create_db.ps1`) — production/shared DB deployments.
	- **`staging/`**: Staging tables, `dbo.ImportFromStaging` stored procedure, and `staging_import.ps1` for BULK INSERT flows.
	- **`tools/`**: Client-side import scripts (`import_csv.ps1`) for machines that cannot place files on the SQL Server host.
	- **`csv_templates/`**: Example CSV files (`members.csv`, `courses.csv`, `rounds.csv`, `holes.csv`) and guidance for formatting.

**Quick Start**

## Golf Stats App

Purpose
-------
This repository contains the golf-stats application: database schemas, import tooling, and CSV templates for tracking golf rounds, players, courses, and hole-by-hole scores.

Repository layout
-----------------
- `db/` — Database artifacts and tooling
	- `sqlite/` — SQLite schema and Python initializer (`schema.sql`, `init_db.py`) for local development and quick testing.
	- `mssql/` — SQL Server schema and creation script (`mssql_schema.sql`, `create_db.ps1`) for production/shared deployments.
	- `staging/` — Staging tables, `dbo.ImportFromStaging` stored procedure, and `staging_import.ps1` for BULK INSERT-based large imports.
	- `tools/` — Client-side import utilities (`import_csv.ps1`) for uploading CSVs from a client machine.
	- `csv_templates/` — Example CSV files (`members.csv`, `courses.csv`, `rounds.csv`, `holes.csv`) and a short guide on expected columns.

Quick start
-----------
SQLite (local development)

```powershell
cd .\db\sqlite
python .\init_db.py --init
python .\init_db.py --sample
python .\init_db.py --show
```

SQL Server (create database and deploy schema)

```powershell
cd .\db\mssql
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql"
```

Large CSV import (server-side BULK INSERT)

```powershell
cd .\db\staging
.\staging_import.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -CsvFolder "..\csv_templates"
```

Client-side CSV import (no server file access)

```powershell
cd .\db\tools
.\import_csv.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats"
```

Important notes
---------------
- BULK INSERT requires the SQL Server service account to be able to read CSV files from the provided path (local or network share). If the server cannot access your files, use the client-side importer or a `bcp`-based uploader.
- Scripts prefer Windows Authentication; avoid embedding plain-text credentials. Use Credential Manager or a secrets store for sensitive credentials.

Recommended next steps
----------------------
- Commit any local changes (I can commit this file for you).  
- Add a `bcp`-based client uploader if you need to push large CSVs from client machines to staging.  
- Add row-level validation/logging in `dbo.ImportFromStaging` for better import diagnostics.

If you'd like, I will commit this README update and run a quick `git status`/`git log -n 5` so you can review the commit. Tell me to proceed.
```powershell
cd .\golf-stats-app\db\sqlite
python .\init_db.py --init
python .\init_db.py --sample
python .\init_db.py --show
```

2. Create a SQL Server database and deploy schema:

```powershell
cd .\golf-stats-app\db\mssql
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql"
```

3. For large CSV imports (server must access CSV paths):

```powershell
cd .\golf-stats-app\db\staging
.\staging_import.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -CsvFolder "..\csv_templates"
```

4. For smaller CSV imports from a client machine (no server file access):

```powershell
cd .\golf-stats-app\db\tools
.\import_csv.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats"
```

Notes & next steps
-
- The repository is organized to keep dev (SQLite) and production (MSSQL) workflows separate. If you want, I can:
	- Add a `bcp`-based client loader that pushes CSVs from your machine to staging without copying files to the server,
	- Add validation/logging to the staging stored proc for row-level errors,
	- Add a simple API or UI to insert/view stats.

If you'd like one of those next steps, tell me which and I'll add a plan and implement it.

