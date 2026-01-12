## golf-stats-app

**Purpose:** This folder contains the golf-stats application utilities: database schemas, import tooling, and CSV templates used to manage golf scores and related data for family members.

**Contents:**
- **`db/`**: Database artifacts and tooling.
	- **`sqlite/`**: SQLite schema and initializer (`schema.sql`, `init_db.py`) — quick local/dev setup.
	- **`mssql/`**: SQL Server schema and creation script (`mssql_schema.sql`, `create_db.ps1`) — production/shared DB deployments.
	- **`staging/`**: Staging tables, `dbo.ImportFromStaging` stored procedure, and `staging_import.ps1` for BULK INSERT flows.
	- **`tools/`**: Client-side import scripts (`import_csv.ps1`) for machines that cannot place files on the SQL Server host.
	- **`csv_templates/`**: Example CSV files (`members.csv`, `courses.csv`, `rounds.csv`, `holes.csv`) and guidance for formatting.

**Quick Start**

- SQLite (local dev):

```powershell
cd .\golf-stats-app\db\sqlite
python .\init_db.py --init
python .\init_db.py --sample
python .\init_db.py --show
```

- SQL Server (create DB and deploy schema):

```powershell
cd .\golf-stats-app\db\mssql
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql"
```

- Bulk staging import (server must access CSVs):

```powershell
cd .\golf-stats-app\db\staging
.\staging_import.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -CsvFolder "..\csv_templates"
```

- Client-side CSV import (no server file access):

```powershell
cd .\golf-stats-app\db\tools
.\import_csv.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats"
```

**Important Notes**
- **BULK INSERT requirement:** Server-side `BULK INSERT` requires the SQL Server service account to be able to read the CSV files (local path or network share). Use the client import if you cannot provide server access.
- **Credentials:** Avoid hard-coded passwords in scripts. Prefer Windows authentication, the Windows Credential Manager, or a secret store.

If you want, I can now:
- Commit these changes to `main` with a descriptive commit message.
- Add a `bcp`-based client uploader, or
- Add row-level validation/logging to the staging stored procedure.

Tell me which next step you'd like.

Top-level folders
-
- `automation/` — automation scripts and configs (Ansible, PowerShell profile snippets, etc.).
- `config-files/` — repository root (this project). Contains the `golf-stats-app/` and other sample folders.
- `golf-stats-app/` — the golf stats application and database utilities. Subfolders of interest:
	- `db/` — database artifacts and tooling. Organized into:
		- `sqlite/` — local SQLite schema and Python initializer (`schema.sql`, `init_db.py`). Good for local dev.
		- `mssql/` — SQL Server schema and creation script (`mssql_schema.sql`, `create_db.ps1`). Use for production or shared DB instances.
		- `staging/` — staging tables and stored procedure for high-volume imports plus `staging_import.ps1` which uses `BULK INSERT`.
		- `tools/` — client-side import utilities (`import_csv.ps1`) for smaller CSV sets where server file access is not available.
		- `csv_templates/` — example CSV templates and README describing expected columns and import flow.
	- `README.md` files inside each `db/*` subfolder explain usage and requirements.
- `sample-stuff/` — misc examples and scratch files.

Quick start (PowerShell)
-
1. Use the SQLite flow for local testing:

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

