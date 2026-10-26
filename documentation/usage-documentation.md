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

The left-hand menu has six pages: **Overview**, **Rounds**, **Players**, **Courses**, **Reports** and **Settings**.

## Overview

The opening page summarises the database:

- Totals for courses, players, rounds and holes scored.
- **Leaderboard:** each player's average score to par per hole, best first. Using a per-hole figure keeps 9 and 18 hole rounds comparable.
- **Most played courses** and the **recent rounds**.

## Players

1. Select **Players** in the menu. The player selector and **Add player** button are at the top of the page.
2. To add someone, select **Add player**, type a name and select **Add player** again. Names must be unique.
3. Pick a player from the drop-down to see:
   - **Profile:** the player's photo, name and Handicap Index. Use **Upload photo** to add a picture (JPEG, PNG or WebP, up to 2 MB) and **Remove photo** to clear it.
   - **Handicap panel:** the scores behind the Handicap Index and a course handicap for each rated course.
   - **Overview cards:** rounds played, holes played, best round, average to par and last played date.
   - **Course stats:** complete rounds, best score, average and last played for each course.
   - **History:** every round with par, strokes and score to par.

Scores to par are shown as `E` (level), `+3` (over, red) or `-1` (under, green).

### Handicaps

The app works out a Handicap Index for each player using the World Handicap System, which Golf Australia uses.

- It needs **3 scores**. Two 9-hole rounds count as one score until an index exists.
- Each course needs a **course rating** and **slope rating** (printed on the scorecard). Rounds on a course without them are ignored and the handicap panel says so.
- The panel shows each score's adjusted gross, differential and a tick against the ones counted. The index is the average of the lowest differentials from the last 20 scores.
- The **course handicap** table shows the strokes the player would receive on each rated course.
- The index also appears in the Overview leaderboard and in the player history report.

This is an estimate for personal use, not an official Golf Australia handicap. The sample courses use made-up ratings. See the [site documentation](site-documentation.md#handicap-calculation) for the full method.

## Courses

The Courses page has an **Add course** button at the top, followed by a tile for each course. Each tile shows the course photo (or its initials), name, number of holes, par, rating and description. Select a tile to open the course.

### Add a course

1. Select **Add course**.
2. Enter the course name and choose **9 holes** or **18 holes**.
3. Optionally add a description, notes and a photo (JPEG, PNG or WebP, up to 2 MB).
4. Enter the **course rating** and **slope rating** from the scorecard if you want handicaps for this course. Enter both or neither. For a 9-hole course use the 9-hole values.
5. For every hole enter the **metres**, **par** (3 to 6) and **stroke index**. The stroke index is the hole's difficulty ranking, and each hole needs a different value between 1 and 18. These are printed on the scorecard.
6. Select **Create course**.

### View or edit a course

On a course page, the profile card shows the photo, name, rating and par, followed by the description, notes and hole table. Use **All courses** at the top to go back to the tiles. Use **Edit course details** at the bottom of the page to change the description, notes, rating and slope, upload a new photo or remove the photo.

Holes and the number of holes cannot be changed after a course is created.

## Rounds

The Rounds page has a **Round** selector and a **New round** button at the top. The selected round shows the course, date, low score, each player's result and a hole-by-hole scorecard for everyone in the round. The **All rounds** table at the bottom lists every result; select a row to jump to that round.

### Record a new round

1. Select **New round**.
2. Choose the **course** and the **date played**.
3. Tick every **player** who took part. For each one you can choose a **marker**, the other player who kept their card. Only players ticked in the round can be markers.
4. Enter each player's strokes for every hole. Par is shown beside each hole to help.
5. Select **Save round**. The new scorecard opens.

Every ticked player needs a score (1 to 20) for every hole. A round is saved completely or not at all.

You need at least one course and one player before you can record a round.

## Reports

The Reports page produces printable reports built from the database views.

| Report | Contents |
| --- | --- |
| **Player history** | Rounds played, holes played, best round and average to par per hole, stats for each course and every round. |
| **Course history** | Photo, par and total metres, description and notes, per-hole statistics (times played, average and best strokes), each player's results and every round. |

1. Choose a player or course and select **Generate report**.
2. Select **Print / Save as PDF**.
3. In the print dialog choose **Save as PDF** as the destination (or pick a printer to print on paper).

The menu and buttons are left out of the printout. The PDF file name defaults to the report title.

## Settings

Use **Settings** to choose which database the app connects to and to see information about it.

| Field | Description |
| --- | --- |
| Server | SQL Server instance, for example `.\SQLEXPRESS`. |
| Database | Database name, normally `GolfStats`. |
| ODBC driver | Chosen from the SQL Server drivers installed on your computer. |
| Authentication | Windows authentication, or SQL Server login with a username and password. |
| Trust server certificate | Tick for local servers using a self-signed certificate. |

Select **Test connection** to check the details, then **Save**. Leave the password blank to keep the one already saved.

### Appearance

The **Appearance** panel, to the right of the database connection form, switches between three themes. Each option has an **Enable** button, and only one can be on at a time (the active one shows **Enabled**).

| Option | Behaviour |
| --- | --- |
| Dark | Always use the dark theme. |
| Light | Always use the light theme. |
| System | Follow your device's light or dark setting, and change when it does. |

The choice is saved in your browser, so it applies on the next visit. Reports always print in the light theme.

### Database information

Below the connection form, the **Database information** panel shows:

- Server name, edition, version and the login the app connects as.
- Database name, state, creation date, compatibility level, recovery model and collation.
- Data and log file sizes, and the number and size of stored course photos.
- For Express editions, how much of the 10 GB data limit is used.
- The size and row count of each table.

Select **Refresh info** to reload it. It also reloads after you save the settings.

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
