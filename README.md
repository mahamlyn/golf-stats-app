# Golf Stats App

Purpose
-------
This folder contains the golf-stats application: database schemas, import tooling, CSV templates, and a minimal web UI for viewing player statistics.

Repository layout
-----------------
- `db/` — Database artifacts and tooling
  - `sqlite/` — SQLite schema and Python initializer (`schema.sql`, `init_db.py`) for local development and quick testing.
  - `mssql/` — SQL Server schema and creation script (`mssql_schema.sql`, `create_db.ps1`) for production/shared deployments.
  - `staging/` — Staging tables, `dbo.ImportFromStaging` stored procedure, and `staging_import.ps1` for BULK INSERT-based large imports.
  - `tools/` — Client-side import utilities (`import_csv.ps1`) for uploading CSVs from a client machine.
  - `csv_templates/` — Example CSV files (`members.csv`, `courses.csv`, `rounds.csv`, `holes.csv`) and a short guide on expected columns.
  - `web/` — Minimal Flask web UI to browse players and view player details (`app.py`, templates, `requirements.txt`).

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

Web UI (minimal Flask app)
--------------------------
The repository now contains a small Flask app in `web/` that displays:
- A players list (from `vw_Player_Summary`) and
- A player detail page with hole averages, recent rounds, performance by course, and handicap estimate.

Quick run (from `golf-stats-app/web`):

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python .\app.py
```

By default the app uses SQLite at `../db/sqlite/golfstats.db`. To use SQL Server, set the `DATABASE_URL` environment variable (see `web/.env.example`).

SQL views used by the web UI
---------------------------
The web UI expects these views to exist (deployed via `db/mssql/mssql_views.sql`):
- `vw_Player_Summary` — per-player aggregates (avg score, rounds played, putts, etc.)
- `vw_Player_HoleAverages` — per-player per-hole averages
- `vw_Player_RecentRounds` — recent rounds with course metadata
- `vw_Player_PerformanceByCourse` — per-player per-course aggregates
- `vw_Player_HandicapEstimate` — simplified handicap-like estimate (best 8 of most recent 20 diffs)

Handicap estimate note
-----------------------
The included `vw_Player_HandicapEstimate` is a simplified estimate using `total_strokes - course_par` differentials. It does NOT use course rating or slope and therefore cannot produce an official USGA handicap index. To compute official differentials and indexes you should add `course_rating` (FLOAT) and `slope` (INT) to `dbo.courses` and compute differentials as `(adjusted_score - course_rating) * 113 / slope`.

Deploying the SQL views
-----------------------
Run the views script against your target database (PowerShell example):

```powershell
Import-Module SqlServer
Invoke-Sqlcmd -ServerInstance "localhost" -Database "GolfStats" -InputFile ".\db\mssql\mssql_views.sql"
```

Important notes
---------------
- `BULK INSERT` requires the SQL Server service account to be able to read CSV files from the provided path (local or network share). Use the client-side importer if server access is unavailable.
- Avoid storing plain-text credentials in scripts. Prefer Windows Authentication, Credential Manager, or a secrets store.

Recommended next steps
----------------------
- Push local commits to the remote repository (`git push origin main`).
- Add `course_rating` and `slope` to `dbo.courses` and update the handicap view to compute official differentials.
- Add search, pagination, or authentication to the web UI.

If you'd like, I can perform any of the recommended next steps — tell me which one and I'll add a plan and implement it.

