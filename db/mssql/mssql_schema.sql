-- MS-SQL schema for golf stats database
-- Designed for SQL Server (T-SQL). Run this against the target database.

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF OBJECT_ID('dbo.members','U') IS NULL
BEGIN
  CREATE TABLE dbo.members (
    id INT IDENTITY(1,1) PRIMARY KEY,
    first_name NVARCHAR(100) NOT NULL,
    last_name NVARCHAR(100) NULL,
    email NVARCHAR(255) NULL UNIQUE,
    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
  );
END

IF OBJECT_ID('dbo.courses','U') IS NULL
BEGIN
  CREATE TABLE dbo.courses (
    id INT IDENTITY(1,1) PRIMARY KEY,
    name NVARCHAR(255) NOT NULL,
    par INT NULL,
    holes INT NULL,
    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
  );
END

IF OBJECT_ID('dbo.rounds','U') IS NULL
BEGIN
  CREATE TABLE dbo.rounds (
    id INT IDENTITY(1,1) PRIMARY KEY,
    member_id INT NOT NULL,
    course_id INT NULL,
    date_played DATE NOT NULL,
    total_strokes INT NULL,
    putts INT NULL,
    fairways_hit INT NULL,
    gir INT NULL,
    notes NVARCHAR(MAX) NULL,
    created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT fk_rounds_member FOREIGN KEY (member_id) REFERENCES dbo.members(id) ON DELETE CASCADE,
    CONSTRAINT fk_rounds_course FOREIGN KEY (course_id) REFERENCES dbo.courses(id) ON DELETE SET NULL
  );
END

IF OBJECT_ID('dbo.holes','U') IS NULL
BEGIN
  CREATE TABLE dbo.holes (
    id INT IDENTITY(1,1) PRIMARY KEY,
    round_id INT NOT NULL,
    hole_number INT NOT NULL,
    par INT NULL,
    strokes INT NULL,
    putts INT NULL,
    fairway_hit INT NULL,
    gir INT NULL,
    CONSTRAINT fk_holes_round FOREIGN KEY (round_id) REFERENCES dbo.rounds(id) ON DELETE CASCADE
  );
END

-- Indexes
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_rounds_member' AND object_id = OBJECT_ID('dbo.rounds'))
BEGIN
  CREATE INDEX idx_rounds_member ON dbo.rounds(member_id);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_holes_round' AND object_id = OBJECT_ID('dbo.holes'))
BEGIN
  CREATE INDEX idx_holes_round ON dbo.holes(round_id);
END

GO
