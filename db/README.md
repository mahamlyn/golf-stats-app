Golf Stats DB

This folder contains a small SQLite-based database for storing golf statistics for family members.

Files:

- `schema.sql` - SQL schema for `members`, `courses`, `rounds`, and `holes` tables.
- `init_db.py` - Python script to create the SQLite DB, load the schema, insert sample data, and provide helper functions.
- `golf_stats.db` - (created after running the initializer)

Quick start (PowerShell):

1. Create the database and schema:

```powershell
python .\golf-stats-app\db\init_db.py --init
```

2. (Optional) Add sample data:

```powershell
python .\golf-stats-app\db\init_db.py --sample
```

3. Show a small summary of members and recent rounds:

```powershell
python .\golf-stats-app\db\init_db.py --show
```

Using the library from other scripts:

```python
from golf_stats_app.db.init_db import connect, add_member, add_round
**DB Layout**: This `db/` folder now contains subfolders for different database workflows.

- `sqlite/` — Local SQLite schema and initializer for development.
- `mssql/`  — SQL Server schema and create script for production/multi-user.
- `staging/` — Staging tables and stored proc for high-volume BULK INSERT imports.
- `tools/` — Importer scripts (CSV-based) and utilities.
- `csv_templates/` — Example CSVs and CSV import README.

See the READMEs in each subfolder for usage examples. Example quick starts:

```powershell
cd .\golf-stats-app\db\sqlite
python .\init_db.py --init

cd ..\mssql
.\create_db.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -SchemaPath ".\mssql_schema.sql"

cd ..\staging
.\staging_import.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -CsvFolder "..\csv_templates"
```

If you'd like I can further reorganize, add CI steps, or provide `bcp`/server-upload helpers for the staging flow.
