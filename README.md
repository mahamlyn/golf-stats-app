# Golf Stats App

Tracks golf scores for 9 or 18 hole courses. Courses are stored with their printed scorecard data (metres, par, stroke index), and one or more players can record scores against a course in a round, so each player can look back at their history.

## Status

Database layer only. There is no application code yet.

## Repository Layout

| Path | Description |
| --- | --- |
| [database/](database/) | SQL Server Express scripts for the `GolfStats` database. |
| [database/README.md](database/README.md) | Script order, ER diagram, views and stored procedures. |
| [database/01_create_schema.sql](database/01_create_schema.sql) | Creates the database, tables, trigger, views and procedures. |
| [database/02_seed_sample_data.sql](database/02_seed_sample_data.sql) | Sample 9-hole course data. |

## Data Model Overview

- **Course / CourseHole:** a course and its holes.
- **Player:** people who play.
- **Round / RoundPlayer:** a group round on a course, with each participating player and an optional marker.
- **RoundScore:** strokes per hole per player.

See the [ER diagram](database/README.md#entity-relationship-diagram) for details.

## Getting Started

1. Install SQL Server Express.
2. Run the scripts in [database/](database/) in order, e.g. `sqlcmd -S .\SQLEXPRESS -E -i database\01_create_schema.sql`.
3. See the [example queries](database/README.md#example) to add players, rounds and scores.
