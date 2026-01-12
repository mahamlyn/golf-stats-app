-- Staging tables and import procedure for bulk CSV imports
-- Run this in the target database (e.g. GolfStats) before performing bulk loads.

SET NOCOUNT ON;

-- Staging tables (simple, mirror of CSV columns)
IF OBJECT_ID('dbo.stg_members','U') IS NULL
BEGIN
  CREATE TABLE dbo.stg_members (
    first_name NVARCHAR(100) NULL,
    last_name NVARCHAR(100) NULL,
    email NVARCHAR(255) NULL
  );
END

IF OBJECT_ID('dbo.stg_courses','U') IS NULL
BEGIN
  CREATE TABLE dbo.stg_courses (
    name NVARCHAR(255) NULL,
    par INT NULL,
    holes INT NULL
  );
END

IF OBJECT_ID('dbo.stg_rounds','U') IS NULL
BEGIN
  CREATE TABLE dbo.stg_rounds (
    ext_round_id NVARCHAR(100) NULL,
    member_email NVARCHAR(255) NULL,
    course_name NVARCHAR(255) NULL,
    date_played DATE NULL,
    total_strokes INT NULL,
    putts INT NULL,
    fairways_hit INT NULL,
    gir INT NULL,
    notes NVARCHAR(MAX) NULL
  );
END

IF OBJECT_ID('dbo.stg_holes','U') IS NULL
BEGIN
  CREATE TABLE dbo.stg_holes (
    ext_round_id NVARCHAR(100) NULL,
    hole_number INT NULL,
    par INT NULL,
    strokes INT NULL,
    putts INT NULL,
    fairway_hit INT NULL,
    gir INT NULL
  );
END

GO

-- Stored procedure to import from staging into production tables
IF OBJECT_ID('dbo.ImportFromStaging','P') IS NOT NULL
  DROP PROCEDURE dbo.ImportFromStaging;
GO

CREATE PROCEDURE dbo.ImportFromStaging
AS
BEGIN
  SET NOCOUNT ON;
  BEGIN TRY
    BEGIN TRANSACTION;

    -- Member map: email -> id
    DECLARE @member_map TABLE (email NVARCHAR(255) PRIMARY KEY, id INT);

    INSERT INTO @member_map (email, id)
    SELECT m.email, m.id
    FROM dbo.members m
    WHERE m.email IS NOT NULL
      AND m.email IN (SELECT DISTINCT email FROM dbo.stg_members WHERE email IS NOT NULL);

    -- Insert new members
    INSERT INTO dbo.members (first_name, last_name, email)
    OUTPUT inserted.email, inserted.id INTO @member_map (email, id)
    SELECT DISTINCT s.first_name, s.last_name, s.email
    FROM dbo.stg_members s
    WHERE s.email IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM @member_map mm WHERE mm.email = s.email);

    -- Course map: name -> id
    DECLARE @course_map TABLE (name NVARCHAR(255) PRIMARY KEY, id INT);

    INSERT INTO @course_map (name, id)
    SELECT c.name, c.id
    FROM dbo.courses c
    WHERE c.name IS NOT NULL
      AND c.name IN (SELECT DISTINCT name FROM dbo.stg_courses WHERE name IS NOT NULL);

    -- Insert new courses
    INSERT INTO dbo.courses (name, par, holes)
    OUTPUT inserted.name, inserted.id INTO @course_map (name, id)
    SELECT DISTINCT s.name, s.par, s.holes
    FROM dbo.stg_courses s
    WHERE s.name IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM @course_map cm WHERE cm.name = s.name);

    -- Insert rounds, capturing inserted id mapped to ext_round_id
    DECLARE @round_map TABLE (ext_round_id NVARCHAR(100) PRIMARY KEY, id INT);

    INSERT INTO dbo.rounds (member_id, course_id, date_played, total_strokes, putts, fairways_hit, gir, notes)
    OUTPUT s.ext_round_id, inserted.id INTO @round_map (ext_round_id, id)
    SELECT
      mm.id AS member_id,
      cm.id AS course_id,
      s.date_played,
      s.total_strokes,
      s.putts,
      s.fairways_hit,
      s.gir,
      s.notes
    FROM dbo.stg_rounds s
    LEFT JOIN @member_map mm ON mm.email = s.member_email
    LEFT JOIN @course_map cm ON cm.name = s.course_name;

    -- Insert holes by joining to round_map
    INSERT INTO dbo.holes (round_id, hole_number, par, strokes, putts, fairway_hit, gir)
    SELECT rm.id AS round_id, h.hole_number, h.par, h.strokes, h.putts, h.fairway_hit, h.gir
    FROM dbo.stg_holes h
    JOIN @round_map rm ON rm.ext_round_id = h.ext_round_id;

    -- Optionally clear staging tables (commented out — uncomment if desired)
    -- TRUNCATE TABLE dbo.stg_holes;
    -- TRUNCATE TABLE dbo.stg_rounds;
    -- TRUNCATE TABLE dbo.stg_courses;
    -- TRUNCATE TABLE dbo.stg_members;

    COMMIT TRANSACTION;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0
      ROLLBACK TRANSACTION;
    DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE();
    RAISERROR('ImportFromStaging failed: %s', 16, 1, @ErrMsg);
  END CATCH
END
GO
