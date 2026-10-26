-- SQL Server Express: creates the GolfStats database, tables and constraints.
-- Safe to re-run: existing database is left untouched.
IF DB_ID(N'GolfStats') IS NULL
    CREATE DATABASE GolfStats;
GO

USE GolfStats;
GO

IF OBJECT_ID(N'dbo.Course', N'U') IS NULL
CREATE TABLE dbo.Course (
    CourseId    INT IDENTITY(1,1) CONSTRAINT PK_Course PRIMARY KEY,
    CourseName  NVARCHAR(100) NOT NULL CONSTRAINT UQ_Course_Name UNIQUE,
    NumHoles    TINYINT       NOT NULL CONSTRAINT CK_Course_NumHoles CHECK (NumHoles IN (9, 18))
);
GO

-- Course details added after the first release; each ALTER is skipped if the column exists.
IF COL_LENGTH(N'dbo.Course', N'Description') IS NULL
    ALTER TABLE dbo.Course ADD Description NVARCHAR(500) NULL;
GO
IF COL_LENGTH(N'dbo.Course', N'Notes') IS NULL
    ALTER TABLE dbo.Course ADD Notes NVARCHAR(MAX) NULL;
GO
IF COL_LENGTH(N'dbo.Course', N'Photo') IS NULL
    ALTER TABLE dbo.Course ADD Photo VARBINARY(MAX) NULL;
GO
IF COL_LENGTH(N'dbo.Course', N'PhotoContentType') IS NULL
    ALTER TABLE dbo.Course ADD PhotoContentType NVARCHAR(100) NULL;
GO
-- Ratings for the holes on the card (9-hole values for a 9-hole course); needed to calculate handicaps.
IF COL_LENGTH(N'dbo.Course', N'CourseRating') IS NULL
    ALTER TABLE dbo.Course ADD CourseRating DECIMAL(4,1) NULL
        CONSTRAINT CK_Course_CourseRating CHECK (CourseRating BETWEEN 18.0 AND 90.0);
GO
IF COL_LENGTH(N'dbo.Course', N'SlopeRating') IS NULL
    ALTER TABLE dbo.Course ADD SlopeRating SMALLINT NULL
        CONSTRAINT CK_Course_SlopeRating CHECK (SlopeRating BETWEEN 55 AND 155);
GO

-- Printed scorecard data: one row per hole per course.
IF OBJECT_ID(N'dbo.CourseHole', N'U') IS NULL
CREATE TABLE dbo.CourseHole (
    CourseId     INT      NOT NULL CONSTRAINT FK_CourseHole_Course REFERENCES dbo.Course(CourseId) ON DELETE CASCADE,
    HoleNumber   TINYINT  NOT NULL CONSTRAINT CK_CourseHole_HoleNumber CHECK (HoleNumber BETWEEN 1 AND 18),
    Metres       SMALLINT NOT NULL CONSTRAINT CK_CourseHole_Metres CHECK (Metres > 0),
    Par          TINYINT  NOT NULL CONSTRAINT CK_CourseHole_Par CHECK (Par BETWEEN 3 AND 6),
    StrokeIndex  TINYINT  NOT NULL CONSTRAINT CK_CourseHole_Index CHECK (StrokeIndex BETWEEN 1 AND 18),
    CONSTRAINT PK_CourseHole PRIMARY KEY (CourseId, HoleNumber),
    CONSTRAINT UQ_CourseHole_Index UNIQUE (CourseId, StrokeIndex)
);
GO

IF OBJECT_ID(N'dbo.Player', N'U') IS NULL
CREATE TABLE dbo.Player (
    PlayerId    INT IDENTITY(1,1) CONSTRAINT PK_Player PRIMARY KEY,
    PlayerName  NVARCHAR(100) NOT NULL CONSTRAINT UQ_Player_Name UNIQUE
);
GO

IF COL_LENGTH(N'dbo.Player', N'Photo') IS NULL
    ALTER TABLE dbo.Player ADD Photo VARBINARY(MAX) NULL;
GO
IF COL_LENGTH(N'dbo.Player', N'PhotoContentType') IS NULL
    ALTER TABLE dbo.Player ADD PhotoContentType NVARCHAR(100) NULL;
GO

-- One row per group round on a course.
IF OBJECT_ID(N'dbo.Round', N'U') IS NULL
CREATE TABLE dbo.Round (
    RoundId   INT IDENTITY(1,1) CONSTRAINT PK_Round PRIMARY KEY,
    CourseId  INT  NOT NULL CONSTRAINT FK_Round_Course REFERENCES dbo.Course(CourseId),
    PlayedOn  DATE NOT NULL CONSTRAINT DF_Round_PlayedOn DEFAULT (CAST(GETDATE() AS DATE))
);
GO

-- Players taking part in a round; marker is optional (the person who keeps their card).
IF OBJECT_ID(N'dbo.RoundPlayer', N'U') IS NULL
CREATE TABLE dbo.RoundPlayer (
    RoundId         INT NOT NULL CONSTRAINT FK_RoundPlayer_Round REFERENCES dbo.Round(RoundId) ON DELETE CASCADE,
    PlayerId        INT NOT NULL CONSTRAINT FK_RoundPlayer_Player REFERENCES dbo.Player(PlayerId),
    MarkerPlayerId  INT NULL     CONSTRAINT FK_RoundPlayer_Marker REFERENCES dbo.Player(PlayerId),
    CONSTRAINT PK_RoundPlayer PRIMARY KEY (RoundId, PlayerId)
);
GO

-- Strokes per hole per player in a round.
IF OBJECT_ID(N'dbo.RoundScore', N'U') IS NULL
CREATE TABLE dbo.RoundScore (
    RoundId     INT     NOT NULL,
    PlayerId    INT     NOT NULL,
    HoleNumber  TINYINT NOT NULL,
    Strokes     TINYINT NOT NULL CONSTRAINT CK_RoundScore_Strokes CHECK (Strokes BETWEEN 1 AND 20),
    CONSTRAINT PK_RoundScore PRIMARY KEY (RoundId, PlayerId, HoleNumber),
    CONSTRAINT FK_RoundScore_RoundPlayer FOREIGN KEY (RoundId, PlayerId)
        REFERENCES dbo.RoundPlayer(RoundId, PlayerId) ON DELETE CASCADE
);
GO

-- Rejects scores for holes that do not exist on the round's course.
CREATE OR ALTER TRIGGER dbo.TR_RoundScore_ValidHole ON dbo.RoundScore
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN dbo.Round r ON r.RoundId = i.RoundId
        LEFT JOIN dbo.CourseHole h ON h.CourseId = r.CourseId AND h.HoleNumber = i.HoleNumber
        WHERE h.HoleNumber IS NULL
    )
    BEGIN
        RAISERROR (N'Hole number does not exist on the round''s course.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;
GO

-- Scorecard-style view: each score alongside the hole's par and the difference.
CREATE OR ALTER VIEW dbo.vRoundScorecard
AS
SELECT  r.RoundId,
        r.PlayedOn,
        r.CourseId,
        c.CourseName,
        s.PlayerId,
        p.PlayerName,
        s.HoleNumber,
        h.Metres,
        h.Par,
        h.StrokeIndex,
        s.Strokes,
        s.Strokes - h.Par AS ToPar
FROM    dbo.RoundScore s
JOIN    dbo.Round r       ON r.RoundId = s.RoundId
JOIN    dbo.Course c      ON c.CourseId = r.CourseId
JOIN    dbo.CourseHole h  ON h.CourseId = r.CourseId AND h.HoleNumber = s.HoleNumber
JOIN    dbo.Player p      ON p.PlayerId = s.PlayerId;
GO

-- One row per round with totals.
CREATE OR ALTER VIEW dbo.vRoundSummary
AS
SELECT  RoundId,
        PlayedOn,
        CourseId,
        CourseName,
        PlayerId,
        PlayerName,
        COUNT(*)      AS HolesScored,
        SUM(Par)      AS TotalPar,
        SUM(Strokes)  AS TotalStrokes,
        SUM(ToPar)    AS TotalToPar
FROM    dbo.vRoundScorecard
GROUP BY RoundId, PlayedOn, CourseId, CourseName, PlayerId, PlayerName;
GO

-- Per-player, per-course stats (best/average/rounds) for complete rounds only.
CREATE OR ALTER VIEW dbo.vPlayerCourseStats
AS
SELECT  s.PlayerId,
        s.PlayerName,
        s.CourseId,
        s.CourseName,
        COUNT(*)                          AS RoundsPlayed,
        MIN(s.TotalStrokes)               AS BestStrokes,
        CAST(AVG(s.TotalStrokes * 1.0) AS DECIMAL(5,1)) AS AverageStrokes,
        MAX(s.PlayedOn)                   AS LastPlayed
FROM    dbo.vRoundSummary s
JOIN    dbo.Course c ON c.CourseId = s.CourseId AND c.NumHoles = s.HolesScored
GROUP BY s.PlayerId, s.PlayerName, s.CourseId, s.CourseName;
GO

-- Per-hole stats for each course across all recorded rounds (used by the course report).
CREATE OR ALTER VIEW dbo.vCourseHoleStats
AS
SELECT  h.CourseId,
        c.CourseName,
        h.HoleNumber,
        h.Metres,
        h.Par,
        h.StrokeIndex,
        COUNT(s.Strokes)                                 AS TimesPlayed,
        CAST(AVG(s.Strokes * 1.0) AS DECIMAL(4,2))       AS AverageStrokes,
        MIN(s.Strokes)                                   AS BestStrokes
FROM    dbo.CourseHole h
JOIN    dbo.Course c ON c.CourseId = h.CourseId
LEFT JOIN dbo.vRoundScorecard s ON s.CourseId = h.CourseId AND s.HoleNumber = h.HoleNumber
GROUP BY h.CourseId, c.CourseName, h.HoleNumber, h.Metres, h.Par, h.StrokeIndex;
GO

-- A player's rounds, newest first (include @CourseId to filter to one course).
CREATE OR ALTER PROCEDURE dbo.usp_GetPlayerHistory
    @PlayerId INT,
    @CourseId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT RoundId, PlayedOn, CourseName, HolesScored, TotalPar, TotalStrokes, TotalToPar
    FROM   dbo.vRoundSummary
    WHERE  PlayerId = @PlayerId
      AND  (@CourseId IS NULL OR CourseId = @CourseId)
    ORDER BY PlayedOn DESC, RoundId DESC;
END;
GO

-- Hole-by-hole scorecard for one round (all players, or one if @PlayerId is given).
CREATE OR ALTER PROCEDURE dbo.usp_GetRoundScorecard
    @RoundId  INT,
    @PlayerId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PlayerName, HoleNumber, Metres, Par, StrokeIndex, Strokes, ToPar
    FROM   dbo.vRoundScorecard
    WHERE  RoundId = @RoundId
      AND  (@PlayerId IS NULL OR PlayerId = @PlayerId)
    ORDER BY PlayerName, HoleNumber;
END;
GO
