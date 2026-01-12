CSV Import Templates

This folder contains CSV templates and an import script to load data into the MS-SQL `GolfStats` database.

Templates:
- `members.csv` — columns: `first_name,last_name,email` (email helps resolve member rows when mapping rounds)
- `courses.csv` — columns: `name,par,holes` (course name used to resolve rounds)
- `rounds.csv` — columns: `ext_round_id,member_email,course_name,date_played,total_strokes,putts,fairways_hit,gir,notes`
  - `ext_round_id` is a temporary identifier used to map holes to the inserted round rows.
  - `member_email` must match an email in `members.csv` (or an existing member in DB).
  - `course_name` must match a name in `courses.csv` (or an existing course in DB).
- `holes.csv` — columns: `ext_round_id,hole_number,par,strokes,putts,fairway_hit,gir`
  - `ext_round_id` refers back to the `ext_round_id` value in `rounds.csv`.

How to use:
1. Ensure the SQL Server database exists and the schema has been deployed (see `README_MSSQL.md`).
2. Place or edit the CSV files in this `csv_templates` folder.
3. Run the importer (PowerShell):

```powershell
cd .\golf-stats-app\db
.\import_csv.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats"
```

Options:
- Use `-Username` and `-Password` to connect with SQL authentication.
- Use `-CsvFolder` to point at a different directory with your CSV files.

Notes:
- The importer bulk-loads `members` and `courses` for speed, then inserts `rounds` and `holes` row-by-row to capture inserted round IDs.
- For production imports or large datasets, consider using `BULK INSERT`/`bcp` and a staging table, then resolve mappings in SQL.
- The import script expects well-formed CSVs; minimal validation is performed.
