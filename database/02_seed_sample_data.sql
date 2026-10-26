-- Sample data: holes 1-9 and 10-16 as printed on the scorecard (17-18 were cut off in the photo).
-- Course name is a placeholder; rename it to match the real course.
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

-- Example usage:
-- INSERT INTO dbo.Player (PlayerName) VALUES (N'Player One'), (N'Player Two');
-- INSERT INTO dbo.Round (CourseId) VALUES (1);
-- INSERT INTO dbo.RoundPlayer (RoundId, PlayerId, MarkerPlayerId) VALUES (1, 1, 2), (1, 2, 1);
-- INSERT INTO dbo.RoundScore (RoundId, PlayerId, HoleNumber, Strokes) VALUES (1, 1, 1, 4), (1, 2, 1, 3);
-- SELECT * FROM dbo.vRoundSummary;
