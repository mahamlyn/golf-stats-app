#!/usr/bin/env python3
"""
Simple SQLite initializer and helper functions for golf stats DB.
Creates `golf_stats.db` next to this script and loads `schema.sql`.
Provides basic functions to add members, courses, rounds, and query sample data.
"""
import sqlite3
import pathlib
import datetime
import json

BASE_DIR = pathlib.Path(__file__).resolve().parent
DB_PATH = BASE_DIR / "golf_stats.db"
SCHEMA_PATH = BASE_DIR / "schema.sql"


def connect(db_path=DB_PATH):
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    # enable foreign key support
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn


def init_db(db_path=DB_PATH, schema_path=SCHEMA_PATH, force=False):
    if db_path.exists() and not force:
        print(f"Database already exists at: {db_path} (use force=True to re-create)")
        return
    if db_path.exists() and force:
        db_path.unlink()
        print(f"Removed existing DB at: {db_path}")

    with connect(db_path) as conn:
        schema_sql = schema_path.read_text()
        conn.executescript(schema_sql)
    print(f"Initialized database at: {db_path}")


# Basic helper functions

def add_member(first_name, last_name=None, email=None, conn=None):
    close = False
    if conn is None:
        conn = connect()
        close = True
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO members (first_name, last_name, email) VALUES (?, ?, ?)",
        (first_name, last_name, email),
    )
    conn.commit()
    member_id = cur.lastrowid
    if close:
        conn.close()
    return member_id


def add_course(name, par=None, holes=None, conn=None):
    close = False
    if conn is None:
        conn = connect()
        close = True
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO courses (name, par, holes) VALUES (?, ?, ?)",
        (name, par, holes),
    )
    conn.commit()
    cid = cur.lastrowid
    if close:
        conn.close()
    return cid


def add_round(member_id, date_played, course_id=None, total_strokes=None, putts=None, fairways_hit=None, gir=None, notes=None, conn=None):
    close = False
    if conn is None:
        conn = connect()
        close = True
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO rounds (member_id, course_id, date_played, total_strokes, putts, fairways_hit, gir, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (member_id, course_id, date_played, total_strokes, putts, fairways_hit, gir, notes),
    )
    conn.commit()
    rid = cur.lastrowid
    if close:
        conn.close()
    return rid


def add_hole(round_id, hole_number, par=None, strokes=None, putts=None, fairway_hit=None, gir=None, conn=None):
    close = False
    if conn is None:
        conn = connect()
        close = True
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO holes (round_id, hole_number, par, strokes, putts, fairway_hit, gir) VALUES (?, ?, ?, ?, ?, ?, ?)",
        (round_id, hole_number, par, strokes, putts, fairway_hit, gir),
    )
    conn.commit()
    hid = cur.lastrowid
    if close:
        conn.close()
    return hid


def sample_data(conn=None):
    close = False
    if conn is None:
        conn = connect()
        close = True
    # create sample members and a course and a round
    alice = add_member("Alice", "Smith", "alice@example.com", conn=conn)
    bob = add_member("Bob", "Jones", "bob@example.com", conn=conn)
    course = add_course("Sunnyvale GC", par=72, holes=18, conn=conn)
    today = datetime.date.today().isoformat()
    r1 = add_round(alice, today, course_id=course, total_strokes=88, putts=36, fairways_hit=8, gir=6, notes="Practice round", conn=conn)
    # add a couple of hole rows for the round
    add_hole(r1, 1, par=4, strokes=5, putts=2, fairway_hit=0, gir=0, conn=conn)
    add_hole(r1, 2, par=3, strokes=3, putts=1, fairway_hit=0, gir=1, conn=conn)
    if close:
        conn.close()
    return {"alice_id": alice, "bob_id": bob, "course_id": course, "round_id": r1}


def show_summary(conn=None):
    close = False
    if conn is None:
        conn = connect()
        close = True
    cur = conn.cursor()
    cur.execute("SELECT id, first_name, last_name, email, created_at FROM members ORDER BY id")
    members = [dict(row) for row in cur.fetchall()]
    cur.execute("SELECT r.id, r.date_played, r.total_strokes, m.first_name || ' ' || m.last_name AS player FROM rounds r JOIN members m ON r.member_id = m.id ORDER BY r.date_played DESC LIMIT 10")
    rounds = [dict(row) for row in cur.fetchall()]
    if close:
        conn.close()
    print(json.dumps({"members": members, "recent_rounds": rounds}, indent=2))


if __name__ == "__main__":
    import argparse

    p = argparse.ArgumentParser(description="Initialize and manage golf stats SQLite DB")
    p.add_argument("--init", action="store_true", help="Create DB and schema (no sample data)")
    p.add_argument("--force", action="store_true", help="Force recreate DB if exists")
    p.add_argument("--sample", action="store_true", help="Insert sample data after init")
    p.add_argument("--show", action="store_true", help="Show summary of members and recent rounds")
    args = p.parse_args()

    if args.init or args.sample or args.force:
        init_db(force=args.force)
    if args.sample:
        conn = connect()
        sample_data(conn=conn)
        conn.close()
        print("Inserted sample data.")
    if args.show:
        show_summary()
    if not (args.init or args.sample or args.show):
        p.print_help()
