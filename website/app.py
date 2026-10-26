"""API for the GolfStats database; also serves the single-page UI."""
import json
import os
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import pyodbc
from flask import Flask, Response, jsonify, request, send_file

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


@app.route("/api/players")
def players():
    return jsonify(query("SELECT PlayerId, PlayerName FROM dbo.Player ORDER BY PlayerName"))


@app.route("/api/courses")
def courses():
    return jsonify(query(
        "SELECT CourseId, CourseName, NumHoles, Description, "
        "CASE WHEN Photo IS NULL THEN 0 ELSE 1 END AS HasPhoto "
        "FROM dbo.Course ORDER BY CourseName"))


@app.route("/api/courses/<int:course_id>", methods=["GET"])
def course(course_id):
    rows = query(
        "SELECT CourseId, CourseName, NumHoles, Description, Notes, "
        "CASE WHEN Photo IS NULL THEN 0 ELSE 1 END AS HasPhoto "
        "FROM dbo.Course WHERE CourseId = ?", (course_id,))
    if not rows:
        return jsonify(error="Course not found."), 404
    return jsonify(rows[0])


@app.route("/api/courses/<int:course_id>", methods=["PUT"])
def update_course(course_id):
    data = request.get_json(force=True)
    description = (data.get("description") or "").strip()[:500] or None
    notes = (data.get("notes") or "").strip() or None
    if execute("UPDATE dbo.Course SET Description = ?, Notes = ? WHERE CourseId = ?",
               (description, notes, course_id)) == 0:
        return jsonify(error="Course not found."), 404
    return jsonify(ok=True)


@app.route("/api/courses/<int:course_id>/photo", methods=["GET"])
def get_photo(course_id):
    with pyodbc.connect(build_conn_str(load_config()), timeout=5) as conn:
        row = conn.execute(
            "SELECT Photo, PhotoContentType FROM dbo.Course WHERE CourseId = ?", (course_id,)).fetchone()
    if not row or row.Photo is None:
        return jsonify(error="No photo."), 404
    return Response(bytes(row.Photo), mimetype=row.PhotoContentType,
                    headers={"X-Content-Type-Options": "nosniff"})


@app.route("/api/courses/<int:course_id>/photo", methods=["PUT"])
def put_photo(course_id):
    content_type = (request.mimetype or "").lower()
    data = request.get_data()
    if content_type not in PHOTO_TYPES:
        return jsonify(error="Photo must be a JPEG, PNG or WebP image."), 400
    if not data or len(data) > MAX_PHOTO_BYTES:
        return jsonify(error="Photo must be between 1 byte and 2 MB."), 400
    if execute("UPDATE dbo.Course SET Photo = ?, PhotoContentType = ? WHERE CourseId = ?",
               (data, content_type, course_id)) == 0:
        return jsonify(error="Course not found."), 404
    return jsonify(ok=True)


@app.route("/api/courses/<int:course_id>/photo", methods=["DELETE"])
def delete_photo(course_id):
    execute("UPDATE dbo.Course SET Photo = NULL, PhotoContentType = NULL WHERE CourseId = ?", (course_id,))
    return jsonify(ok=True)


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
        "SELECT PlayerName, COUNT(*) AS Rounds, "
        "CAST(SUM(TotalToPar) * 1.0 / SUM(HolesScored) AS DECIMAL(5,2)) AS AvgToParPerHole "
        "FROM dbo.vRoundSummary GROUP BY PlayerName ORDER BY AvgToParPerHole")
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
            "INSERT INTO dbo.Course (CourseName, NumHoles, Description, Notes) "
            "OUTPUT INSERTED.CourseId VALUES (?, ?, ?, ?)",
            name, num_holes, description, notes).fetchone()[0]
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


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5001)
