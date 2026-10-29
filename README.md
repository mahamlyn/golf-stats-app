<p align="center">
  <img src="images/golf-stats.jpg" alt="Golf Stats" width="100%">
</p>

# Golf Stats App

Tracks golf scores for 9 or 18 hole courses. Courses are stored with their printed scorecard data (metres, par, stroke index), a description, notes and a photo. One or more players can record scores against a course in a round, so each player can look back at their history.

## Features

- Overview page with totals, a leaderboard, most played courses and recent rounds.
- Add players, courses (with a photo) and rounds from the browser.
- Hole-by-hole scorecards for every round, with multiple players and markers.
- Per-player stats and history, including best and average scores for each course.
- Database connection configurable from the Settings page.

## Status

Working: a SQL Server Express database and a local web app. Editing or deleting existing records is not available yet.

## Repository Layout

| Path | Description |
| --- | --- |
| [database/](database/) | SQL Server Express scripts for the `GolfStats` database. |
| [database/README.md](database/README.md) | Script order, ER diagram, views and stored procedures. |
| [database/01_create_schema.sql](database/01_create_schema.sql) | Creates the database, tables, trigger, views and procedures. |
| [database/02_seed_sample_data.sql](database/02_seed_sample_data.sql) | Sample courses, players, rounds and scores. |
| [website/](website/) | Flask API and single-page web app (see the [website README](website/README.md)). |
| [documentation/](documentation/) | [Usage guide](documentation/usage-documentation.md), [site documentation](documentation/site-documentation.md) and [IIS / SQL Express deployment guide](documentation/iis-sql-express-deployment.md). |
| [scripts/](scripts/) | [Script README](scripts/README.md), prerequisite installer and deployment script. |
| [images/](images/) | Images used in the documentation. |

## Data Model Overview

- **Course / CourseHole:** a course and its holes.
- **Player:** people who play.
- **Round / RoundPlayer:** a group round on a course, with each participating player and an optional marker.
- **RoundScore:** strokes per hole per player.

See the [ER diagram](database/README.md#entity-relationship-diagram) for details.

## Getting Started

1. Install SQL Server Express, Python 3 and the Microsoft ODBC Driver for SQL Server.
2. Run the scripts in [database/](database/) in order: `01_create_schema.sql`, then `02_seed_sample_data.sql` for sample data.
3. Start the web app:

   ```powershell
   cd website
   pip install -r requirements.txt
   python app.py
   ```

4. Open http://127.0.0.1:5001. If the database is not on `.\SQLEXPRESS`, use the **Settings** page to set the connection.

See the [usage guide](documentation/usage-documentation.md) for a walkthrough, the [site documentation](documentation/site-documentation.md) for the API and architecture, and the [IIS / SQL Express deployment guide](documentation/iis-sql-express-deployment.md) for Windows Server hosting requirements.
