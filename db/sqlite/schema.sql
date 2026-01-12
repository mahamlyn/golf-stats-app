-- Schema for golf stats database

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS members (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  first_name TEXT NOT NULL,
  last_name TEXT,
  email TEXT UNIQUE,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS courses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  par INTEGER,
  holes INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS rounds (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  member_id INTEGER NOT NULL,
  course_id INTEGER,
  date_played TEXT NOT NULL,
  total_strokes INTEGER,
  putts INTEGER,
  fairways_hit INTEGER,
  gir INTEGER,
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY(member_id) REFERENCES members(id) ON DELETE CASCADE,
  FOREIGN KEY(course_id) REFERENCES courses(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS holes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  round_id INTEGER NOT NULL,
  hole_number INTEGER NOT NULL,
  par INTEGER,
  strokes INTEGER,
  putts INTEGER,
  fairway_hit INTEGER,
  gir INTEGER,
  FOREIGN KEY(round_id) REFERENCES rounds(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_rounds_member ON rounds(member_id);
CREATE INDEX IF NOT EXISTS idx_holes_round ON holes(round_id);
