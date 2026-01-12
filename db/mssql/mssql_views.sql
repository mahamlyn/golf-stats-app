-- Player statistics views for GolfStats (MS-SQL)
-- Adds summary, hole-averages, recent rounds, and performance-by-course views.
-- Safe to run multiple times (drops if exists then creates).

SET NOCOUNT ON;

-- Player summary: per-member aggregates (round counts, avg/min/max scores, putts, fairways, GIR, avg vs par)
IF OBJECT_ID('dbo.vw_Player_Summary', 'V') IS NOT NULL
  DROP VIEW dbo.vw_Player_Summary;
GO

CREATE VIEW dbo.vw_Player_Summary
AS
SELECT
  m.id AS member_id,
  m.first_name,
  m.last_name,
  m.email,
  COUNT(r.id) AS rounds_played,
  MIN(r.date_played) AS first_round_date,
  MAX(r.date_played) AS last_round_date,
  AVG(CAST(r.total_strokes AS FLOAT)) AS avg_score,
  MIN(r.total_strokes) AS best_score,
  MAX(r.total_strokes) AS worst_score,
  AVG(CAST(r.putts AS FLOAT)) AS avg_putts,
  SUM(COALESCE(r.fairways_hit,0)) AS total_fairways_hit,
  AVG(CAST(r.fairways_hit AS FLOAT)) AS avg_fairways_hit,
  AVG(CAST(r.gir AS FLOAT)) AS avg_gir,
  AVG(CAST(r.total_strokes - c.par AS FLOAT)) AS avg_to_par
FROM dbo.members m
LEFT JOIN dbo.rounds r ON r.member_id = m.id
LEFT JOIN dbo.courses c ON r.course_id = c.id
GROUP BY m.id, m.first_name, m.last_name, m.email;
GO

-- Hole averages: per-member per-hole statistics across all recorded holes
IF OBJECT_ID('dbo.vw_Player_HoleAverages', 'V') IS NOT NULL
  DROP VIEW dbo.vw_Player_HoleAverages;
GO

CREATE VIEW dbo.vw_Player_HoleAverages
AS
SELECT
  m.id AS member_id,
  m.first_name,
  m.last_name,
  h.hole_number,
  AVG(CAST(h.strokes AS FLOAT)) AS avg_strokes,
  MIN(h.strokes) AS best_strokes,
  MAX(h.strokes) AS worst_strokes,
  AVG(CAST(h.putts AS FLOAT)) AS avg_putts,
  COUNT_BIG(*) AS hole_count,
  AVG(CAST(h.par AS FLOAT)) AS avg_par
FROM dbo.holes h
INNER JOIN dbo.rounds r ON h.round_id = r.id
INNER JOIN dbo.members m ON r.member_id = m.id
GROUP BY m.id, m.first_name, m.last_name, h.hole_number;
GO

-- Recent rounds: rounds with member and course metadata (use this view and ORDER BY when querying)
IF OBJECT_ID('dbo.vw_Player_RecentRounds', 'V') IS NOT NULL
  DROP VIEW dbo.vw_Player_RecentRounds;
GO

CREATE VIEW dbo.vw_Player_RecentRounds
AS
SELECT
  r.id AS round_id,
  r.member_id,
  m.first_name,
  m.last_name,
  r.course_id,
  c.name AS course_name,
  r.date_played,
  r.total_strokes,
  r.putts,
  r.fairways_hit,
  r.gir,
  r.notes,
  r.created_at
FROM dbo.rounds r
LEFT JOIN dbo.members m ON r.member_id = m.id
LEFT JOIN dbo.courses c ON r.course_id = c.id;
GO

-- Performance by course: per-member per-course aggregates
IF OBJECT_ID('dbo.vw_Player_PerformanceByCourse', 'V') IS NOT NULL
  DROP VIEW dbo.vw_Player_PerformanceByCourse;
GO

CREATE VIEW dbo.vw_Player_PerformanceByCourse
AS
SELECT
  m.id AS member_id,
  m.first_name,
  m.last_name,
  c.id AS course_id,
  c.name AS course_name,
  COUNT(r.id) AS rounds_played,
  AVG(CAST(r.total_strokes AS FLOAT)) AS avg_score,
  MIN(r.total_strokes) AS best_score,
  MAX(r.total_strokes) AS worst_score
FROM dbo.rounds r
INNER JOIN dbo.members m ON r.member_id = m.id
LEFT JOIN dbo.courses c ON r.course_id = c.id
WHERE r.total_strokes IS NOT NULL
GROUP BY m.id, m.first_name, m.last_name, c.id, c.name;
GO

-- End of views

-- Handicap estimate view
-- Note: This is a simplified handicap-like estimate because the schema does not include
-- course rating/slope required for an official USGA handicap. The view computes
-- round differentials as (total_strokes - course_par), considers up to the most
-- recent 20 rounds per player, selects the best 8 differentials (or all if fewer
-- than 8), averages them, and applies a 0.96 multiplier (common adjustment factor).
IF OBJECT_ID('dbo.vw_Player_HandicapEstimate', 'V') IS NOT NULL
  DROP VIEW dbo.vw_Player_HandicapEstimate;
GO

CREATE VIEW dbo.vw_Player_HandicapEstimate
AS
WITH recent AS (
  SELECT
    r.id,
    r.member_id,
    r.date_played,
    r.total_strokes,
    c.par,
    CAST(r.total_strokes - c.par AS FLOAT) AS diff,
    ROW_NUMBER() OVER (PARTITION BY r.member_id ORDER BY r.date_played DESC, r.id DESC) AS rn,
    COUNT(*) OVER (PARTITION BY r.member_id) AS total_rounds_all
  FROM dbo.rounds r
  LEFT JOIN dbo.courses c ON r.course_id = c.id
  WHERE r.total_strokes IS NOT NULL AND c.par IS NOT NULL
),
recent20 AS (
  SELECT * FROM recent WHERE rn <= 20
),
ranked AS (
  SELECT
    r20.*,
    ROW_NUMBER() OVER (PARTITION BY member_id ORDER BY diff ASC, date_played DESC, id DESC) AS diff_rank,
    COUNT(*) OVER (PARTITION BY member_id) AS recent_count
  FROM recent20 r20
),
best AS (
  -- If recent_count >= 8, take best 8 diffs; otherwise take all recent diffs
  SELECT * FROM ranked
  WHERE (recent_count >= 8 AND diff_rank <= 8) OR (recent_count < 8)
)
SELECT
  m.id AS member_id,
  m.first_name,
  m.last_name,
  COALESCE(MAX(b.recent_count), 0) AS rounds_considered,
  COALESCE(MAX(b.total_rounds_all), 0) AS rounds_total,
  CASE WHEN COUNT(b.diff) = 0 THEN NULL ELSE ROUND(AVG(b.diff) * 0.96, 2) END AS handicap_estimate
FROM dbo.members m
LEFT JOIN best b ON b.member_id = m.id
GROUP BY m.id, m.first_name, m.last_name;
GO
