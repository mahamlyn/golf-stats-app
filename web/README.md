golf-stats-app — web UI
=======================

Small Flask web UI to view player statistics from the GolfStats database.

Quick start (local, uses SQLite by default)

1. Create a virtual environment and install deps:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

2. Start the app (defaults to SQLite path `../db/sqlite/golfstats.db`):

```powershell
# from the `web` folder
python .\app.py
```

3. Open http://localhost:5000/ and view players.

Using SQL Server

Set `DATABASE_URL` to an appropriate SQLAlchemy connection string (see `.env.example`). Recommended is `mssql+pyodbc` with an ODBC driver installed on the system. Then run the app the same way.

Notes

- The app reads data from the views created earlier (`vw_Player_Summary`, `vw_Player_HoleAverages`, `vw_Player_RecentRounds`, `vw_Player_PerformanceByCourse`, `vw_Player_HandicapEstimate`). Make sure `mssql_views.sql` has been deployed to your database.
- This is a minimal demo — if you'd like I can add authentication, filtering, pagination, or a small API.