"""API for the GolfStats database; also serves the single-page UI."""
import json
import os
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import pyodbc
from flask import Flask, Response, jsonify, redirect, request, send_file

import handicap

MAX_PHOTO_BYTES = 2 * 1024 * 1024
# SVG is excluded on purpose: it can carry scripts.
PHOTO_TYPES = {"image/jpeg", "image/png", "image/webp"}

CONFIG_PATH = Path(__file__).with_name("config.json")
DEFAULTS = {
    "server": os.environ.get("GOLF_DB_SERVER", r".\SQLEXPRESS"),
    "database": "GolfStats",
    "driver": os.environ.get("GOLF_DB_DRIVER", "ODBC Driver 18 for SQL Server"),
    "auth": "windows",  # "windows" or "sql"
    "username": "",
    "password": "",
    "trust_server_certificate": True,
}

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = MAX_PHOTO_BYTES + 1024


def load_config():
    cfg = dict(DEFAULTS)
    if CONFIG_PATH.exists():
        cfg.update(json.loads(CONFIG_PATH.read_text(encoding="utf-8")))
    return cfg


def odbc_value(value):
    # Braces stop values containing ';' from injecting extra connection attributes.
    return "{" + str(value).replace("}", "}}") + "}"


def build_conn_str(cfg):
    parts = [
        f"DRIVER={odbc_value(cfg['driver'])}",
        f"SERVER={odbc_value(cfg['server'])}",
        f"DATABASE={odbc_value(cfg['database'])}",
        f"TrustServerCertificate={'yes' if cfg['trust_server_certificate'] else 'no'}",
    ]
    if cfg["auth"] == "sql":
        parts += [f"UID={odbc_value(cfg['username'])}", f"PWD={odbc_value(cfg['password'])}"]
    else:
        parts.append("Trusted_Connection=yes")
    return ";".join(parts) + ";"


def query(sql, params=()):
    with pyodbc.connect(build_conn_str(load_config()), timeout=5) as conn:
        cur = conn.cursor()
        cur.execute(sql, params)
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, map(to_json, row))) for row in cur.fetchall()]


def execute(sql, params=()):
    with pyodbc.connect(build_conn_str(load_config()), timeout=5) as conn:
        rows = conn.execute(sql, params).rowcount
        conn.commit()
        return rows


def transaction(work):
    conn = pyodbc.connect(build_conn_str(load_config()), timeout=5)
    try:
        result = work(conn.cursor())
        conn.commit()
        return result
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


class InputError(Exception):
    pass


def as_int(value, label, lo, hi):
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise InputError(f"{label} must be a whole number.")
    try:
        number = int(value)
    except ValueError:
        raise InputError(f"{label} must be a whole number.") from None
    if not lo <= number <= hi:
        raise InputError(f"{label} must be between {lo} and {hi}.")
    return number


def as_text(value, label, max_len, required=True):
    text = str(value or "").strip()
    if required and not text:
        raise InputError(f"{label} is required.")
    if len(text) > max_len:
        raise InputError(f"{label} must be {max_len} characters or fewer.")
    return text or None


def json_body():
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        raise InputError("Request body must be a JSON object.")
    return data


@app.errorhandler(InputError)
def input_error(e):
    return jsonify(error=str(e)), 400


@app.errorhandler(pyodbc.IntegrityError)
def integrity_error(e):
    return jsonify(error="Could not save: that name already exists or a referenced record is missing."), 409


def to_json(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return value


def clean_config(data, current):
    cfg = {
        "server": str(data.get("server", "")).strip(),
        "database": str(data.get("database", "")).strip(),
        "driver": str(data.get("driver", "")).strip(),
        "auth": "sql" if data.get("auth") == "sql" else "windows",
        "username": str(data.get("username", "")).strip(),
        "password": data.get("password") or "",
        "trust_server_certificate": bool(data.get("trust_server_certificate", True)),
    }
    # Blank password in the form means keep the saved one.
    if not cfg["password"] and cfg["auth"] == "sql":
        cfg["password"] = current.get("password", "")
    if not cfg["server"] or not cfg["database"] or not cfg["driver"]:
        raise ValueError("Server, database and driver are required.")
    if cfg["auth"] == "sql" and not cfg["username"]:
        raise ValueError("Username is required for SQL authentication.")
    return cfg


@app.route("/api/config", methods=["GET"])
def get_config():
    cfg = load_config()
    cfg["has_password"] = bool(cfg.pop("password"))
    cfg["available_drivers"] = [d for d in pyodbc.drivers() if "SQL Server" in d]
    return jsonify(cfg)


@app.route("/api/config", methods=["PUT"])
def save_config():
    try:
        cfg = clean_config(request.get_json(force=True), load_config())
    except ValueError as e:
        return jsonify(error=str(e)), 400
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    return jsonify(ok=True)


@app.route("/api/config/test", methods=["POST"])
def test_config():
    try:
        cfg = clean_config(request.get_json(force=True), load_config())
        with pyodbc.connect(build_conn_str(cfg), timeout=5) as conn:
            conn.execute("SELECT 1")
    except (ValueError, pyodbc.Error) as e:
        return jsonify(ok=False, error=str(e))
    return jsonify(ok=True)


@app.errorhandler(pyodbc.Error)
def db_error(e):
    return jsonify(error="Database connection failed. Check the Settings tab. " + str(e)), 500


@app.route("/")
def index():
    return send_file(Path(__file__).with_name("index.html"))


@app.route("/favicon.svg")
def favicon():
    return send_file(Path(__file__).with_name("favicon.svg"), mimetype="image/svg+xml")


@app.route("/favicon.ico")
def favicon_ico():
    return redirect("/favicon.svg")


@app.route("/api/players")
def players():
    return jsonify(query(
        "SELECT PlayerId, PlayerName, CASE WHEN Photo IS NULL THEN 0 ELSE 1 END AS HasPhoto "
        "FROM dbo.Player ORDER BY PlayerName"))


def load_rounds(player_id=None):
    """Complete rounds per player, built from vRoundScorecard and the course ratings."""
    sql = ("SELECT s.PlayerId, s.RoundId, s.PlayedOn, s.CourseName, c.NumHoles, c.CourseRating, c.SlopeRating, "
           "s.Par, s.StrokeIndex, s.Strokes FROM dbo.vRoundScorecard s "
           "JOIN dbo.Course c ON c.CourseId = s.CourseId")
    params = ()
    if player_id is not None:
        sql += " WHERE s.PlayerId = ?"
        params = (player_id,)
    rows = query(sql + " ORDER BY s.PlayerId, s.RoundId, s.HoleNumber", params)

    grouped = {}
    for r in rows:
        rounds_for_player = grouped.setdefault(r["PlayerId"], {})
        current = rounds_for_player.get(r["RoundId"])
        if current is None:
            current = rounds_for_player[r["RoundId"]] = handicap.Round(
                r["RoundId"], date.fromisoformat(r["PlayedOn"][:10]), r["CourseName"], r["NumHoles"],
                r["CourseRating"], r["SlopeRating"])
        current.holes.append(handicap.Hole(r["Par"], r["StrokeIndex"], r["Strokes"]))
    return {pid: [x for x in by_round.values() if len(x.holes) == x.num_holes]
            for pid, by_round in grouped.items()}


@app.route("/api/handicaps")
def handicaps():
    return jsonify({str(pid): handicap.calculate(rounds)["index"] for pid, rounds in load_rounds().items()})


@app.route("/api/players/<int:player_id>/handicap")
def player_handicap(player_id):
    result = handicap.calculate(load_rounds(player_id).get(player_id, []))
    rated = query(
        "SELECT c.CourseName, c.NumHoles, c.CourseRating, c.SlopeRating, "
        "(SELECT SUM(Par) FROM dbo.CourseHole WHERE CourseId = c.CourseId) AS Par "
        "FROM dbo.Course c WHERE c.CourseRating IS NOT NULL AND c.SlopeRating IS NOT NULL ORDER BY c.CourseName")
    index = result["index"]
    result["courses"] = [dict(c, CourseHandicap=None if index is None else handicap.course_handicap(
        index, c["CourseRating"], c["SlopeRating"], c["Par"], c["NumHoles"])) for c in rated]
    return jsonify(result)


def photo_response(table, key, item_id):
    with pyodbc.connect(build_conn_str(load_config()), timeout=5) as conn:
        row = conn.execute(f"SELECT Photo, PhotoContentType FROM dbo.{table} WHERE {key} = ?", (item_id,)).fetchone()
    if not row or row.Photo is None:
        return jsonify(error="No photo."), 404
    return Response(bytes(row.Photo), mimetype=row.PhotoContentType,
                    headers={"X-Content-Type-Options": "nosniff"})


def store_photo(table, key, item_id, label):
    content_type = (request.mimetype or "").lower()
    data = request.get_data()
    if content_type not in PHOTO_TYPES:
        return jsonify(error="Photo must be a JPEG, PNG or WebP image."), 400
    if not data or len(data) > MAX_PHOTO_BYTES:
        return jsonify(error="Photo must be between 1 byte and 2 MB."), 400
    if execute(f"UPDATE dbo.{table} SET Photo = ?, PhotoContentType = ? WHERE {key} = ?",
               (data, content_type, item_id)) == 0:
        return jsonify(error=f"{label} not found."), 404
    return jsonify(ok=True)


def clear_photo(table, key, item_id):
    execute(f"UPDATE dbo.{table} SET Photo = NULL, PhotoContentType = NULL WHERE {key} = ?", (item_id,))
    return jsonify(ok=True)


@app.route("/api/players/<int:player_id>/photo", methods=["GET"])
def get_player_photo(player_id):
    return photo_response("Player", "PlayerId", player_id)


@app.route("/api/players/<int:player_id>/photo", methods=["PUT"])
def put_player_photo(player_id):
    return store_photo("Player", "PlayerId", player_id, "Player")


@app.route("/api/players/<int:player_id>/photo", methods=["DELETE"])
def delete_player_photo(player_id):
    return clear_photo("Player", "PlayerId", player_id)


def parse_ratings(body):
    rating, slope = body.get("courseRating"), body.get("slopeRating")
    blank = lambda v: v is None or str(v).strip() == ""
    if blank(rating) and blank(slope):
        return None, None
    if blank(rating) or blank(slope):
        raise InputError("Enter both the course rating and the slope rating, or leave both blank.")
    try:
        rating = round(float(rating), 1)
    except (TypeError, ValueError):
        raise InputError("Course rating must be a number.") from None
    if not 18.0 <= rating <= 90.0:
        raise InputError("Course rating must be between 18.0 and 90.0.")
    return rating, as_int(slope, "Slope rating", 55, 155)


@app.route("/api/courses")
def courses():
    return jsonify(query(
        "SELECT CourseId, CourseName, NumHoles, Description, CourseRating, SlopeRating, "
        "CASE WHEN Photo IS NULL THEN 0 ELSE 1 END AS HasPhoto "
        "FROM dbo.Course ORDER BY CourseName"))


@app.route("/api/courses/<int:course_id>", methods=["GET"])
def course(course_id):
    rows = query(
        "SELECT CourseId, CourseName, NumHoles, Description, Notes, CourseRating, SlopeRating, "
        "CASE WHEN Photo IS NULL THEN 0 ELSE 1 END AS HasPhoto "
        "FROM dbo.Course WHERE CourseId = ?", (course_id,))
    if not rows:
        return jsonify(error="Course not found."), 404
    return jsonify(rows[0])


@app.route("/api/courses/<int:course_id>", methods=["PUT"])
def update_course(course_id):
    data = json_body()
    description = as_text(data.get("description"), "Description", 500, required=False)
    notes = as_text(data.get("notes"), "Notes", 5000, required=False)
    rating, slope = parse_ratings(data)
    if execute("UPDATE dbo.Course SET Description = ?, Notes = ?, CourseRating = ?, SlopeRating = ? WHERE CourseId = ?",
               (description, notes, rating, slope, course_id)) == 0:
        return jsonify(error="Course not found."), 404
    return jsonify(ok=True)


@app.route("/api/courses/<int:course_id>/photo", methods=["GET"])
def get_photo(course_id):
    return photo_response("Course", "CourseId", course_id)


@app.route("/api/courses/<int:course_id>/photo", methods=["PUT"])
def put_photo(course_id):
    return store_photo("Course", "CourseId", course_id, "Course")


@app.route("/api/courses/<int:course_id>/photo", methods=["DELETE"])
def delete_photo(course_id):
    return clear_photo("Course", "CourseId", course_id)


@app.route("/api/overview")
def overview():
    totals = query(
        "SELECT (SELECT COUNT(*) FROM dbo.Course) AS Courses, "
        "(SELECT COUNT(*) FROM dbo.Player) AS Players, "
        "(SELECT COUNT(*) FROM dbo.Round) AS Rounds, "
        "(SELECT COUNT(*) FROM dbo.RoundScore) AS HolesScored")[0]
    recent = query(
        "SELECT TOP 6 RoundId, PlayedOn, CourseName, PlayerName, HolesScored, TotalStrokes, TotalToPar "
        "FROM dbo.vRoundSummary ORDER BY PlayedOn DESC, RoundId DESC, TotalToPar")
    leaderboard = query(
        "SELECT PlayerId, PlayerName, COUNT(*) AS Rounds, "
        "CAST(SUM(TotalToPar) * 1.0 / SUM(HolesScored) AS DECIMAL(5,2)) AS AvgToParPerHole "
        "FROM dbo.vRoundSummary GROUP BY PlayerId, PlayerName ORDER BY AvgToParPerHole")
    indexes = {pid: handicap.calculate(rounds)["index"] for pid, rounds in load_rounds().items()}
    for row in leaderboard:
        row["HandicapIndex"] = indexes.get(row["PlayerId"])
    popular = query(
        "SELECT TOP 5 CourseName, COUNT(DISTINCT RoundId) AS Rounds, MAX(PlayedOn) AS LastPlayed "
        "FROM dbo.vRoundSummary GROUP BY CourseName ORDER BY Rounds DESC, CourseName")
    return jsonify(totals=totals, recent=recent, leaderboard=leaderboard, popular=popular)


@app.route("/api/courses/<int:course_id>/holes")
def course_holes(course_id):
    return jsonify(query(
        "SELECT HoleNumber, Metres, Par, StrokeIndex FROM dbo.CourseHole "
        "WHERE CourseId = ? ORDER BY HoleNumber", (course_id,)))


@app.route("/api/rounds")
def rounds():
    return jsonify(query(
        "SELECT RoundId, CONVERT(varchar(10), PlayedOn, 23) AS PlayedOn, CourseName, PlayerName, "
        "HolesScored, TotalPar, TotalStrokes, TotalToPar "
        "FROM dbo.vRoundSummary ORDER BY PlayedOn DESC, RoundId DESC, PlayerName"))


@app.route("/api/rounds/<int:round_id>/scorecard")
def scorecard(round_id):
    return jsonify(query(
        "SELECT PlayerName, HoleNumber, Metres, Par, StrokeIndex, Strokes, ToPar "
        "FROM dbo.vRoundScorecard WHERE RoundId = ? ORDER BY PlayerName, HoleNumber", (round_id,)))


@app.route("/api/players/<int:player_id>/history")
def player_history(player_id):
    return jsonify(query("EXEC dbo.usp_GetPlayerHistory @PlayerId = ?", (player_id,)))


@app.route("/api/players/<int:player_id>/stats")
def player_stats(player_id):
    return jsonify(query(
        "SELECT CourseName, RoundsPlayed, BestStrokes, AverageStrokes, LastPlayed "
        "FROM dbo.vPlayerCourseStats WHERE PlayerId = ? ORDER BY CourseName", (player_id,)))


@app.route("/api/players", methods=["POST"])
def add_player():
    name = as_text(json_body().get("name"), "Player name", 100)
    row = transaction(lambda cur: cur.execute(
        "INSERT INTO dbo.Player (PlayerName) OUTPUT INSERTED.PlayerId VALUES (?)", name).fetchone())
    return jsonify(PlayerId=row[0], PlayerName=name), 201


@app.route("/api/courses", methods=["POST"])
def add_course():
    body = json_body()
    name = as_text(body.get("name"), "Course name", 100)
    num_holes = as_int(body.get("numHoles"), "Number of holes", 9, 18)
    if num_holes not in (9, 18):
        raise InputError("Number of holes must be 9 or 18.")
    description = as_text(body.get("description"), "Description", 500, required=False)
    notes = as_text(body.get("notes"), "Notes", 5000, required=False)
    rating, slope = parse_ratings(body)

    holes = body.get("holes")
    if not isinstance(holes, list) or len(holes) != num_holes:
        raise InputError(f"Details for all {num_holes} holes are required.")
    parsed = []
    for number, hole in enumerate(holes, 1):
        if not isinstance(hole, dict):
            raise InputError(f"Hole {number} is invalid.")
        parsed.append((
            number,
            as_int(hole.get("metres"), f"Hole {number} metres", 1, 2000),
            as_int(hole.get("par"), f"Hole {number} par", 3, 6),
            as_int(hole.get("strokeIndex"), f"Hole {number} stroke index", 1, 18),
        ))
    if len({h[3] for h in parsed}) != num_holes:
        raise InputError("Each hole needs a different stroke index.")

    def work(cur):
        course_id = cur.execute(
            "INSERT INTO dbo.Course (CourseName, NumHoles, Description, Notes, CourseRating, SlopeRating) "
            "OUTPUT INSERTED.CourseId VALUES (?, ?, ?, ?, ?, ?)",
            name, num_holes, description, notes, rating, slope).fetchone()[0]
        for number, metres, par, stroke_index in parsed:
            cur.execute(
                "INSERT INTO dbo.CourseHole (CourseId, HoleNumber, Metres, Par, StrokeIndex) VALUES (?, ?, ?, ?, ?)",
                course_id, number, metres, par, stroke_index)
        return course_id

    return jsonify(CourseId=transaction(work)), 201


@app.route("/api/rounds", methods=["POST"])
def add_round():
    body = json_body()
    course_id = as_int(body.get("courseId"), "Course", 1, 2**31 - 1)
    try:
        played_on = datetime.strptime(str(body.get("playedOn")), "%Y-%m-%d").date()
    except ValueError:
        raise InputError("Date must be in YYYY-MM-DD format.") from None
    entries = body.get("players")
    if not isinstance(entries, list) or not entries:
        raise InputError("At least one player is required.")

    def work(cur):
        row = cur.execute("SELECT NumHoles FROM dbo.Course WHERE CourseId = ?", course_id).fetchone()
        if row is None:
            raise InputError("Course not found.")
        num_holes = row[0]

        parsed = []
        for entry in entries:
            if not isinstance(entry, dict):
                raise InputError("Player entry is invalid.")
            player_id = as_int(entry.get("playerId"), "Player", 1, 2**31 - 1)
            marker = entry.get("markerPlayerId")
            marker = None if marker in (None, "") else as_int(marker, "Marker", 1, 2**31 - 1)
            scores = entry.get("scores")
            if not isinstance(scores, list) or len(scores) != num_holes:
                raise InputError(f"A score for each of the {num_holes} holes is required.")
            parsed.append((player_id, marker, [as_int(s, "Score", 1, 20) for s in scores]))

        ids = [p[0] for p in parsed]
        if len(set(ids)) != len(ids):
            raise InputError("A player can only be added once.")
        for player_id, marker, _ in parsed:
            if marker is not None and (marker == player_id or marker not in ids):
                raise InputError("A marker must be a different player in the same round.")

        round_id = cur.execute(
            "INSERT INTO dbo.Round (CourseId, PlayedOn) OUTPUT INSERTED.RoundId VALUES (?, ?)",
            course_id, played_on.isoformat()).fetchone()[0]
        for player_id, marker, _ in parsed:
            cur.execute("INSERT INTO dbo.RoundPlayer (RoundId, PlayerId, MarkerPlayerId) VALUES (?, ?, ?)",
                        round_id, player_id, marker)
        for player_id, _, scores in parsed:
            for hole, strokes in enumerate(scores, 1):
                cur.execute("INSERT INTO dbo.RoundScore (RoundId, PlayerId, HoleNumber, Strokes) VALUES (?, ?, ?, ?)",
                            round_id, player_id, hole, strokes)
        return round_id

    return jsonify(RoundId=transaction(work)), 201


@app.route("/api/reports/player/<int:player_id>")
def report_player(player_id):
    player = query("SELECT PlayerId, PlayerName FROM dbo.Player WHERE PlayerId = ?", (player_id,))
    if not player:
        return jsonify(error="Player not found."), 404
    stats = query(
        "SELECT CourseName, RoundsPlayed, BestStrokes, AverageStrokes, LastPlayed "
        "FROM dbo.vPlayerCourseStats WHERE PlayerId = ? ORDER BY CourseName", (player_id,))
    rounds = query(
        "SELECT RoundId, PlayedOn, CourseName, HolesScored, TotalPar, TotalStrokes, TotalToPar "
        "FROM dbo.vRoundSummary WHERE PlayerId = ? ORDER BY PlayedOn DESC, RoundId DESC", (player_id,))
    return jsonify(player=player[0], stats=stats, rounds=rounds)


@app.route("/api/reports/course/<int:course_id>")
def report_course(course_id):
    course_rows = query(
        "SELECT c.CourseId, c.CourseName, c.NumHoles, c.Description, c.Notes, c.CourseRating, c.SlopeRating, "
        "CASE WHEN c.Photo IS NULL THEN 0 ELSE 1 END AS HasPhoto, "
        "(SELECT SUM(Par) FROM dbo.CourseHole WHERE CourseId = c.CourseId) AS TotalPar, "
        "(SELECT SUM(Metres) FROM dbo.CourseHole WHERE CourseId = c.CourseId) AS TotalMetres "
        "FROM dbo.Course c WHERE c.CourseId = ?", (course_id,))
    if not course_rows:
        return jsonify(error="Course not found."), 404
    holes = query(
        "SELECT HoleNumber, Metres, Par, StrokeIndex, TimesPlayed, AverageStrokes, BestStrokes "
        "FROM dbo.vCourseHoleStats WHERE CourseId = ? ORDER BY HoleNumber", (course_id,))
    players = query(
        "SELECT PlayerName, RoundsPlayed, BestStrokes, AverageStrokes, LastPlayed "
        "FROM dbo.vPlayerCourseStats WHERE CourseId = ? ORDER BY BestStrokes, PlayerName", (course_id,))
    rounds = query(
        "SELECT RoundId, PlayedOn, PlayerName, HolesScored, TotalPar, TotalStrokes, TotalToPar "
        "FROM dbo.vRoundSummary WHERE CourseId = ? ORDER BY PlayedOn DESC, RoundId DESC, TotalStrokes", (course_id,))
    return jsonify(course=course_rows[0], holes=holes, players=players, rounds=rounds)


@app.route("/api/database/info")
def database_info():
    # Express editions cap data files (not logs) at 10 GB.
    express_limit_mb = 10 * 1024
    server = query(
        "SELECT CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(200)) AS ServerName, "
        "CAST(SERVERPROPERTY('Edition') AS NVARCHAR(200)) AS Edition, "
        "CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50)) AS Version, "
        "SUSER_SNAME() AS LoginName")[0]
    db = query(
        "SELECT name AS Name, create_date AS Created, compatibility_level AS CompatibilityLevel, "
        "recovery_model_desc AS RecoveryModel, collation_name AS Collation, state_desc AS State "
        "FROM sys.databases WHERE name = DB_NAME()")[0]
    files = query(
        "SELECT type_desc AS Type, name AS Name, CAST(size * 8 / 1024.0 AS DECIMAL(12,2)) AS SizeMB "
        "FROM sys.database_files ORDER BY type, file_id")
    tables = query(
        "SELECT t.name AS Name, "
        "(SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = t.object_id AND p.index_id IN (0, 1)) AS [Rows], "
        "CAST((SELECT SUM(a.total_pages) FROM sys.partitions p "
        "JOIN sys.allocation_units a ON a.container_id = p.partition_id "
        "WHERE p.object_id = t.object_id) * 8 / 1024.0 AS DECIMAL(12,2)) AS SizeMB "
        "FROM sys.tables t ORDER BY SizeMB DESC, t.name")
    photos = query(
        "SELECT COUNT(Photo) AS Count, CAST(ISNULL(SUM(DATALENGTH(Photo)), 0) / 1048576.0 AS DECIMAL(12,2)) AS SizeMB "
        "FROM dbo.Course")[0]
    data_mb = sum(f["SizeMB"] for f in files if f["Type"] == "ROWS")
    log_mb = sum(f["SizeMB"] for f in files if f["Type"] == "LOG")
    is_express = "express" in (server["Edition"] or "").lower()
    return jsonify(server=server, database=db, files=files, tables=tables, photos=photos,
                   dataMB=round(data_mb, 2), logMB=round(log_mb, 2),
                   limitMB=express_limit_mb if is_express else None)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5001)
