# Basic Test App

Single-page viewer ([index.html](index.html)) for the `GolfStats` database. Browsers cannot connect to SQL Server directly, so [app.py](app.py) provides a small read-only Flask API and serves the page.

## Prerequisites

- `GolfStats` database created with the [database scripts](../database/README.md)
- Python 3 and the Microsoft ODBC Driver 18 for SQL Server

## Run

```powershell
pip install -r requirements.txt
python app.py
```

Open http://127.0.0.1:5001, then use the **Settings** tab to set the server, database, ODBC driver and authentication (Windows or SQL login). Use **Test connection** before saving.

Settings are saved to `config.json` next to `app.py` (git-ignored). A SQL login password is stored there in plain text, so only use this for local testing. Defaults are `.\SQLEXPRESS`, `GolfStats`, `ODBC Driver 18 for SQL Server` and Windows authentication; `GOLF_DB_SERVER` and `GOLF_DB_DRIVER` override the first and third.

## Pages

- **Overview:** totals, leaderboard, most played courses and recent rounds.
- **Reports:** printable player history and course history reports; use **Print / Save as PDF**.
- **Settings:** database connection configuration, an **Appearance** panel (Dark, Light or System theme) and a database information panel (versions, sizes, row counts).
- **Rounds:** all rounds with totals; select a row for the hole-by-hole scorecard. **New round** records a round: pick a course and date, tick the players (each can have a marker) and enter every hole's score.
- **Players:** a selector and **Add player** button at the top, then the player's photo, Handicap Index (World Handicap System), the scores behind it, course stats and round history. **Add player** creates a new player.
- **Courses:** a course selector and **Add course** at the top, then the course photo, rating and par, description, notes and holes. **Add course** creates a 9 or 18 hole course with metres, par and stroke index for each hole. The page also edits the description, notes, rating, slope and photo (JPEG, PNG or WebP, max 2 MB). Re-run the database scripts first so the new course columns exist.
