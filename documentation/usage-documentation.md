# Usage Guide

How to run and use the Golf Stats web app.

## Before you start

1. SQL Server Express is installed and the `GolfStats` database exists. See the [database README](../database/README.md) for the scripts and the order to run them.
2. Python 3 and the Microsoft ODBC Driver for SQL Server are installed.

## Starting the app

```powershell
cd golf-stats-app\website
pip install -r requirements.txt
python app.py
```

Open http://127.0.0.1:5001 in a browser. The app only listens on your own computer. Stop it with `Ctrl+C` in the terminal.

If you change `app.py`, stop and restart it. The server does not reload by itself.

## Navigation

The left-hand menu has five pages: **Overview**, **Rounds**, **Players**, **Courses** and **Settings**.

## Overview

The opening page summarises the database:

- Totals for courses, players, rounds and holes scored.
- **Leaderboard:** each player's average score to par per hole, best first. Using a per-hole figure keeps 9 and 18 hole rounds comparable.
- **Most played courses** and the **recent rounds**.

## Players

1. Select **Players** in the menu.
2. To add someone, select **Add player**, type a name and select **Add player** again. Names must be unique.
3. Pick a player from the drop-down to see:
   - **Overview cards:** rounds played, holes played, best round, average to par and last played date.
   - **Course stats:** complete rounds, best score, average and last played for each course.
   - **History:** every round with par, strokes and score to par.

Scores to par are shown as `E` (level), `+3` (over, red) or `-1` (under, green).

## Courses

The Courses page shows a card for each course with its photo and description.

### Add a course

1. Select **Add course**.
2. Enter the course name and choose **9 holes** or **18 holes**.
3. Optionally add a description, notes and a photo (JPEG, PNG or WebP, up to 2 MB).
4. For every hole enter the **metres**, **par** (3 to 6) and **stroke index**. The stroke index is the hole's difficulty ranking, and each hole needs a different value between 1 and 18. These are printed on the scorecard.
5. Select **Create course**.

### View or edit a course

Select a course card to see its photo, description, notes and hole table. Use **Edit course details** at the bottom of the page to change the description and notes, upload a new photo or remove the photo.

Holes and the number of holes cannot be changed after a course is created.

## Rounds

The Rounds page lists every player's result for each round. Select a row to open the hole-by-hole scorecard for everyone in that round.

### Record a new round

1. Select **New round**.
2. Choose the **course** and the **date played**.
3. Tick every **player** who took part. For each one you can choose a **marker**, the other player who kept their card. Only players ticked in the round can be markers.
4. Enter each player's strokes for every hole. Par is shown beside each hole to help.
5. Select **Save round**. The new scorecard opens.

Every ticked player needs a score (1 to 20) for every hole. A round is saved completely or not at all.

You need at least one course and one player before you can record a round.

## Settings

Use **Settings** to choose which database the app connects to:

| Field | Description |
| --- | --- |
| Server | SQL Server instance, for example `.\SQLEXPRESS`. |
| Database | Database name, normally `GolfStats`. |
| ODBC driver | Chosen from the SQL Server drivers installed on your computer. |
| Authentication | Windows authentication, or SQL Server login with a username and password. |
| Trust server certificate | Tick for local servers using a self-signed certificate. |

Select **Test connection** to check the details, then **Save**. Leave the password blank to keep the one already saved.

## Troubleshooting

| Problem | Likely cause and fix |
| --- | --- |
| A page shows `Request failed: 404` | The server is running old code. Stop it and run `python app.py` again. |
| "Database connection failed" | Open **Settings** and use **Test connection**. Check the server name, that SQL Server is running, and the authentication method. |
| Driver not found | Install the Microsoft ODBC Driver for SQL Server, then pick it in **Settings**. |
| Invalid column name errors | The database is missing newer columns. Re-run `01_create_schema.sql`; it is safe to re-run. |
| "That name already exists" | Player and course names must be unique. |
| Photo rejected | Use a JPEG, PNG or WebP image no larger than 2 MB. |

## What the app cannot do yet

- Edit or delete players, rounds, hole details or courses. Do this directly in SQL for now.
- Save a round with some holes left blank.
- Handle logins or several users. Anyone who can open the page can change data, so keep it on your own computer.
