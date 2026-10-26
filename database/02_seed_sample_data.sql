-- Sample data: three courses, three players and five rounds with scores.
-- The Par 3 course uses holes 1-9 from the scorecard photo; its name is a placeholder.
USE GolfStats;
GO

INSERT INTO dbo.Course (CourseName, NumHoles)
SELECT N'Sample Par 3 Course', 9
WHERE NOT EXISTS (SELECT 1 FROM dbo.Course WHERE CourseName = N'Sample Par 3 Course');
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE CourseName = N'Sample Par 3 Course');

IF NOT EXISTS (SELECT 1 FROM dbo.CourseHole WHERE CourseId = @CourseId)
INSERT INTO dbo.CourseHole (CourseId, HoleNumber, Metres, Par, StrokeIndex)
VALUES
    (@CourseId, 1,  71, 3, 17),
    (@CourseId, 2,  78, 3,  6),
    (@CourseId, 3,  80, 3, 13),
    (@CourseId, 4,  74, 3, 15),
    (@CourseId, 5,  68, 3,  9),
    (@CourseId, 6,  96, 3, 11),
    (@CourseId, 7,  70, 3, 10),
    (@CourseId, 8, 126, 3,  2),
    (@CourseId, 9,  71, 3,  7);
GO

INSERT INTO dbo.Course (CourseName, NumHoles)
SELECT v.CourseName, v.NumHoles
FROM (VALUES (N'Sample Parkland 9', 9), (N'Sample Championship 18', 18)) AS v(CourseName, NumHoles)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Course c WHERE c.CourseName = v.CourseName);
GO

DECLARE @Parkland INT = (SELECT CourseId FROM dbo.Course WHERE CourseName = N'Sample Parkland 9');
DECLARE @Champ    INT = (SELECT CourseId FROM dbo.Course WHERE CourseName = N'Sample Championship 18');

IF NOT EXISTS (SELECT 1 FROM dbo.CourseHole WHERE CourseId = @Parkland)
INSERT INTO dbo.CourseHole (CourseId, HoleNumber, Metres, Par, StrokeIndex)
VALUES
    (@Parkland, 1, 340, 4, 11),
    (@Parkland, 2, 365, 4,  5),
    (@Parkland, 3, 150, 3, 17),
    (@Parkland, 4, 480, 5,  3),
    (@Parkland, 5, 320, 4, 13),
    (@Parkland, 6, 165, 3, 15),
    (@Parkland, 7, 390, 4,  7),
    (@Parkland, 8, 510, 5,  1),
    (@Parkland, 9, 355, 4,  9);

IF NOT EXISTS (SELECT 1 FROM dbo.CourseHole WHERE CourseId = @Champ)
INSERT INTO dbo.CourseHole (CourseId, HoleNumber, Metres, Par, StrokeIndex)
VALUES
    (@Champ,  1, 360, 4,  7), (@Champ,  2, 385, 4,  3), (@Champ,  3, 150, 3, 15),
    (@Champ,  4, 495, 5,  1), (@Champ,  5, 340, 4, 11), (@Champ,  6, 375, 4,  5),
    (@Champ,  7, 165, 3, 17), (@Champ,  8, 330, 4, 13), (@Champ,  9, 510, 5,  9),
    (@Champ, 10, 400, 4,  8), (@Champ, 11, 175, 3, 16), (@Champ, 12, 355, 4,  4),
    (@Champ, 13, 480, 5,  2), (@Champ, 14, 370, 4, 12), (@Champ, 15, 160, 3, 18),
    (@Champ, 16, 390, 4,  6), (@Champ, 17, 345, 4, 14), (@Champ, 18, 520, 5, 10);
GO

-- Fill in descriptions and notes only where they are still empty.
UPDATE dbo.Course SET
    Description = N'Short 9-hole par 3 course, ideal for practising iron play.',
    Notes = N'Hole 8 is the longest at 126m and plays into the prevailing wind. Greens are small and firm in summer.'
WHERE CourseName = N'Sample Par 3 Course' AND Description IS NULL;

UPDATE dbo.Course SET
    Description = N'Relaxed 9-hole parkland layout with wide fairways.',
    Notes = N'The 4th and 8th are the par 5s. Water comes into play on the 6th.'
WHERE CourseName = N'Sample Parkland 9' AND Description IS NULL;

UPDATE dbo.Course SET
    Description = N'Full 18-hole championship course, par 72.',
    Notes = N'Stroke index 1 is the 4th. Bunkers guard most greens; the closing hole is a long par 5.'
WHERE CourseName = N'Sample Championship 18' AND Description IS NULL;
GO

-- Sample ratings only; replace them with the real figures printed on the scorecard.
UPDATE dbo.Course SET CourseRating = 25.6, SlopeRating = 80  WHERE CourseName = N'Sample Par 3 Course'     AND CourseRating IS NULL;
UPDATE dbo.Course SET CourseRating = 35.4, SlopeRating = 118 WHERE CourseName = N'Sample Parkland 9'      AND CourseRating IS NULL;
UPDATE dbo.Course SET CourseRating = 73.1, SlopeRating = 130 WHERE CourseName = N'Sample Championship 18' AND CourseRating IS NULL;
GO

INSERT INTO dbo.Player (PlayerName)
SELECT v.PlayerName
FROM (VALUES (N'Alex'), (N'Sam'), (N'Jordan')) AS v(PlayerName)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Player p WHERE p.PlayerName = v.PlayerName);
GO

-- Rounds are only seeded once.
IF NOT EXISTS (SELECT 1 FROM dbo.Round)
BEGIN
    DECLARE @Alex INT = (SELECT PlayerId FROM dbo.Player WHERE PlayerName = N'Alex');
    DECLARE @Sam INT = (SELECT PlayerId FROM dbo.Player WHERE PlayerName = N'Sam');
    DECLARE @Jordan INT = (SELECT PlayerId FROM dbo.Player WHERE PlayerName = N'Jordan');
    DECLARE @Par3 INT = (SELECT CourseId FROM dbo.Course WHERE CourseName = N'Sample Par 3 Course');
    DECLARE @ParklandId INT = (SELECT CourseId FROM dbo.Course WHERE CourseName = N'Sample Parkland 9');
    DECLARE @ChampId INT = (SELECT CourseId FROM dbo.Course WHERE CourseName = N'Sample Championship 18');
    DECLARE @R1 INT, @R2 INT, @R3 INT;

    -- Round 1: Alex and Sam on the Par 3 course, marking each other.
    INSERT INTO dbo.Round (CourseId, PlayedOn) VALUES (@Par3, '2026-09-05');
    SET @R1 = SCOPE_IDENTITY();
    INSERT INTO dbo.RoundPlayer (RoundId, PlayerId, MarkerPlayerId)
    VALUES (@R1, @Alex, @Sam), (@R1, @Sam, @Alex);
    INSERT INTO dbo.RoundScore (RoundId, PlayerId, HoleNumber, Strokes)
    SELECT @R1, p.PlayerId, s.HoleNumber, CASE p.PlayerId WHEN @Alex THEN s.Alex ELSE s.Sam END
    FROM (VALUES (1,5,6),(2,3,5),(3,6,6),(4,5,3),(5,5,3),(6,6,5),(7,4,4),(8,5,4),(9,4,5)) AS s(HoleNumber, Alex, Sam)
    CROSS JOIN (VALUES (@Alex), (@Sam)) AS p(PlayerId);

    -- Round 2: Alex and Sam on the Parkland 9.
    INSERT INTO dbo.Round (CourseId, PlayedOn) VALUES (@ParklandId, '2026-09-19');
    SET @R2 = SCOPE_IDENTITY();
    INSERT INTO dbo.RoundPlayer (RoundId, PlayerId, MarkerPlayerId)
    VALUES (@R2, @Alex, @Sam), (@R2, @Sam, @Alex);
    INSERT INTO dbo.RoundScore (RoundId, PlayerId, HoleNumber, Strokes)
    SELECT @R2, p.PlayerId, s.HoleNumber, CASE p.PlayerId WHEN @Alex THEN s.Alex ELSE s.Sam END
    FROM (VALUES (1,5,4),(2,4,5),(3,3,4),(4,6,6),(5,4,5),(6,4,3),(7,5,4),(8,6,7),(9,4,5)) AS s(HoleNumber, Alex, Sam)
    CROSS JOIN (VALUES (@Alex), (@Sam)) AS p(PlayerId);

    -- Round 3: all three players on the Championship 18.
    INSERT INTO dbo.Round (CourseId, PlayedOn) VALUES (@ChampId, '2026-10-10');
    SET @R3 = SCOPE_IDENTITY();
    INSERT INTO dbo.RoundPlayer (RoundId, PlayerId, MarkerPlayerId)
    VALUES (@R3, @Alex, @Sam), (@R3, @Sam, @Jordan), (@R3, @Jordan, @Alex);
    INSERT INTO dbo.RoundScore (RoundId, PlayerId, HoleNumber, Strokes)
    SELECT @R3, p.PlayerId, s.HoleNumber,
           CASE p.PlayerId WHEN @Alex THEN s.Alex WHEN @Sam THEN s.Sam ELSE s.Jordan END
    FROM (VALUES
        (1,5,4,5),(2,4,5,4),(3,3,3,4),(4,6,6,5),(5,4,5,4),(6,5,4,5),
        (7,3,4,3),(8,4,5,4),(9,5,6,6),(10,4,4,5),(11,3,3,3),(12,5,4,4),
        (13,6,5,6),(14,4,5,4),(15,4,3,3),(16,4,5,4),(17,5,4,5),(18,5,6,5)
    ) AS s(HoleNumber, Alex, Sam, Jordan)
    CROSS JOIN (VALUES (@Alex), (@Sam), (@Jordan)) AS p(PlayerId);
END
GO

-- Two more rounds so Alex and Sam have enough scores for a Handicap Index.
IF NOT EXISTS (SELECT 1 FROM dbo.Round WHERE PlayedOn = '2026-10-17')
BEGIN
    DECLARE @A INT = (SELECT PlayerId FROM dbo.Player WHERE PlayerName = N'Alex');
    DECLARE @S INT = (SELECT PlayerId FROM dbo.Player WHERE PlayerName = N'Sam');
    DECLARE @Course INT = (SELECT CourseId FROM dbo.Course WHERE CourseName = N'Sample Championship 18');
    DECLARE @R4 INT, @R5 INT;

    INSERT INTO dbo.Round (CourseId, PlayedOn) VALUES (@Course, '2026-10-17');
    SET @R4 = SCOPE_IDENTITY();
    INSERT INTO dbo.RoundPlayer (RoundId, PlayerId, MarkerPlayerId) VALUES (@R4, @A, @S), (@R4, @S, @A);
    INSERT INTO dbo.RoundScore (RoundId, PlayerId, HoleNumber, Strokes)
    SELECT @R4, p.PlayerId, s.HoleNumber, CASE p.PlayerId WHEN @A THEN s.Alex ELSE s.Sam END
    FROM (VALUES
        (1,5,5),(2,4,5),(3,3,4),(4,6,5),(5,4,5),(6,5,5),(7,4,3),(8,4,4),(9,5,6),
        (10,4,5),(11,3,3),(12,5,4),(13,6,5),(14,4,5),(15,3,4),(16,4,5),(17,5,4),(18,5,6)
    ) AS s(HoleNumber, Alex, Sam)
    CROSS JOIN (VALUES (@A), (@S)) AS p(PlayerId);

    INSERT INTO dbo.Round (CourseId, PlayedOn) VALUES (@Course, '2026-10-24');
    SET @R5 = SCOPE_IDENTITY();
    INSERT INTO dbo.RoundPlayer (RoundId, PlayerId, MarkerPlayerId) VALUES (@R5, @A, @S), (@R5, @S, @A);
    INSERT INTO dbo.RoundScore (RoundId, PlayerId, HoleNumber, Strokes)
    SELECT @R5, p.PlayerId, s.HoleNumber, CASE p.PlayerId WHEN @A THEN s.Alex ELSE s.Sam END
    FROM (VALUES
        (1,4,5),(2,4,4),(3,3,4),(4,5,6),(5,4,5),(6,5,4),(7,3,4),(8,5,4),(9,5,5),
        (10,4,4),(11,4,3),(12,4,5),(13,6,5),(14,4,5),(15,3,3),(16,5,4),(17,4,5),(18,5,5)
    ) AS s(HoleNumber, Alex, Sam)
    CROSS JOIN (VALUES (@A), (@S)) AS p(PlayerId);
END
GO

-- Check the results:
-- SELECT * FROM dbo.vRoundSummary ORDER BY PlayedOn, PlayerName;
-- SELECT * FROM dbo.vPlayerCourseStats;
-- EXEC dbo.usp_GetPlayerHistory @PlayerId = 1;
