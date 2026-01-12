SQLite Database

This folder contains the SQLite schema and initializer for local/dev use.

Files:
- `schema.sql` — SQLite schema for `members`, `courses`, `rounds`, and `holes`.
- `init_db.py` — Python helper to create the DB, load schema, and insert sample data.

Quick start (PowerShell):

```powershell
cd .\golf-stats-app\db\sqlite
python .\init_db.py --init
python .\init_db.py --sample
python .\init_db.py --show
```

Use this folder for a local single-file DB during development. For multi-user or production usage, see the `../mssql` folder.
