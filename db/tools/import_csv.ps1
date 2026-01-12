<#
Import CSV templates into SQL Server database.

Behavior:
- Imports `members.csv` and `courses.csv` in bulk.
- Imports `rounds.csv` row-by-row and requires an `ext_round_id` column which is used to map inserted round IDs for holes.
- Imports `holes.csv` row-by-row and uses `ext_round_id` to find the correct `round_id`.

CSV location defaults to the `csv_templates` subfolder next to this script.

Usage:
# Windows auth (default)
cd <repo>\golf-stats-app\db\tools
..\..\db\tools\import_csv.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats"

# SQL auth
..\..\db\tools\import_csv.ps1 -ServerInstance "localhost,1433" -DatabaseName "GolfStats" -Username "sa" -Password "P@ssw0rd"

# To point at another folder of CSVs
..\..\db\tools\import_csv.ps1 -ServerInstance "localhost" -DatabaseName "GolfStats" -CsvFolder ".\\mycsvs"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ServerInstance = 'localhost',

    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = 'GolfStats',

    [Parameter(Mandatory=$false)]
    [string]$CsvFolder = (Join-Path $PSScriptRoot '..\csv_templates'),

    [Parameter(Mandatory=$false)]
    [string]$Username,

    [Parameter(Mandatory=$false)]
    [string]$Password
)

function Ensure-Module {
    param([string]$Name)
    if (-not (Get-Module -ListAvailable -Name $Name)) {
        Write-Host "Module '$Name' not found. Installing to CurrentUser..."
        try {
            Install-Module -Name $Name -Scope CurrentUser -Force -ErrorAction Stop
        }
        catch {
            Write-Error "Failed to install module '$Name'. Run PowerShell as admin or install the SqlServer module manually. Error: $_"
            throw
        }
    }
}

function EscapeSql($s) {
    if ($null -eq $s) { return $null }
    return $s -replace "'","''"
}

Ensure-Module -Name 'SqlServer'

if (-not (Test-Path $CsvFolder)) {
    Write-Error "CSV folder not found: $CsvFolder"
    exit 1
}

# wrapper for Invoke-Sqlcmd with optional SQL auth
function Invoke-Sql {
    param(
        [string]$Server,
        [string]$Database,
        [string]$Query
    )
    $params = @{ ServerInstance = $Server }
    if ($Database) { $params['Database'] = $Database }
    if ($PSBoundParameters.ContainsKey('Username') -and $Username) {
        $params['Username'] = $Username
        $params['Password'] = $Password
    }
    $params['Query'] = $Query
    return Invoke-Sqlcmd @params
}

try {
    Write-Host "Importing CSVs from: $CsvFolder to $ServerInstance\$DatabaseName"

    # 1) Members (bulk)
    $membersPath = Join-Path $CsvFolder 'members.csv'
    if (Test-Path $membersPath) {
        $members = Import-Csv $membersPath | Select-Object first_name,last_name,email
        if ($members.Count -gt 0) {
            Write-Host "Importing members: $($members.Count) rows"
            Write-SqlTableData -ServerInstance $ServerInstance -Database $DatabaseName -SchemaName 'dbo' -TableName 'members' -InputData $members -Force
        }
    }

    # 2) Courses (bulk)
    $coursesPath = Join-Path $CsvFolder 'courses.csv'
    if (Test-Path $coursesPath) {
        $courses = Import-Csv $coursesPath | Select-Object name,par,holes
        if ($courses.Count -gt 0) {
            Write-Host "Importing courses: $($courses.Count) rows"
            Write-SqlTableData -ServerInstance $ServerInstance -Database $DatabaseName -SchemaName 'dbo' -TableName 'courses' -InputData $courses -Force
        }
    }

    # Prepare lookup maps
    $memberMap = @{}
    $courseMap = @{}

    $memRows = Invoke-Sql -Server $ServerInstance -Database $DatabaseName -Query "SELECT id, email FROM dbo.members WHERE email IS NOT NULL"
    foreach ($r in $memRows) { $memberMap[$r.email.ToLower()] = $r.id }
    $courseRows = Invoke-Sql -Server $ServerInstance -Database $DatabaseName -Query "SELECT id, name FROM dbo.courses WHERE name IS NOT NULL"
    foreach ($r in $courseRows) { $courseMap[$r.name.ToLower()] = $r.id }

    # 3) Rounds (row-by-row, capture inserted IDs using OUTPUT)
    $roundsPath = Join-Path $CsvFolder 'rounds.csv'
    $roundExtMap = @{} # ext_round_id -> inserted id
    if (Test-Path $roundsPath) {
        $roundRows = Import-Csv $roundsPath
        Write-Host "Importing rounds: $($roundRows.Count) rows"
        foreach ($row in $roundRows) {
            $ext = $row.ext_round_id
            if (-not $ext) { Write-Warning "Row missing ext_round_id; skipping: $($row | ConvertTo-Json -Compress)"; continue }
            $memberEmail = $row.member_email
            $courseName = $row.course_name
            $memberId = $null
            $courseId = $null
            if ($memberEmail) {
                $memberMapKey = $memberEmail.ToLower()
                if ($memberMap.ContainsKey($memberMapKey)) { $memberId = $memberMap[$memberMapKey] }
                else { Write-Warning "Member not found for email $memberEmail; skipping round $ext"; continue }
            }
            if ($courseName) {
                $courseMapKey = $courseName.ToLower()
                if ($courseMap.ContainsKey($courseMapKey)) { $courseId = $courseMap[$courseMapKey] }
                else { Write-Warning "Course not found for name $courseName; setting NULL"; $courseId = $null }
            }
            $datePlayed = $row.date_played
            $totalStrokes = if ($row.total_strokes -ne '') { [int]$row.total_strokes } else { $null }
            $putts = if ($row.putts -ne '') { [int]$row.putts } else { $null }
            $fairwaysHit = if ($row.fairways_hit -ne '') { [int]$row.fairways_hit } else { $null }
            $gir = if ($row.gir -ne '') { [int]$row.gir } else { $null }
            $notes = $row.notes -replace "'","''"

            $q = @"
SET NOCOUNT ON;
DECLARE @InsertedIds TABLE (id INT);
INSERT INTO dbo.rounds (member_id, course_id, date_played, total_strokes, putts, fairways_hit, gir, notes)
OUTPUT INSERTED.id INTO @InsertedIds
VALUES ($($memberId -as [string] -ne '' ? $memberId : 'NULL'), $($courseId -as [string] -ne '' ? $courseId : 'NULL'), '$([EscapeSql]::Invoke($datePlayed))', $($totalStrokes -ne $null ? $totalStrokes : 'NULL'), $($putts -ne $null ? $putts : 'NULL'), $($fairwaysHit -ne $null ? $fairwaysHit : 'NULL'), $($gir -ne $null ? $gir : 'NULL'), N'$notes');
SELECT id FROM @InsertedIds;
"@

            # Because we can't call EscapeSql from the here-string, use manual building
            $dateEsc = if ($datePlayed) { EscapeSql($datePlayed) } else { '' }
            $notesEsc = if ($notes) { $notes } else { '' }
            $memberVal = if ($memberId) { $memberId } else { 'NULL' }
            $courseVal = if ($courseId) { $courseId } else { 'NULL' }
            $totalVal = if ($totalStrokes -ne $null) { $totalStrokes } else { 'NULL' }
            $puttsVal = if ($putts -ne $null) { $putts } else { 'NULL' }
            $fairwaysVal = if ($fairwaysHit -ne $null) { $fairwaysHit } else { 'NULL' }
            $girVal = if ($gir -ne $null) { $gir } else { 'NULL' }

            $q2 = "SET NOCOUNT ON; DECLARE @InsertedIds TABLE (id INT); INSERT INTO dbo.rounds (member_id, course_id, date_played, total_strokes, putts, fairways_hit, gir, notes) OUTPUT INSERTED.id INTO @InsertedIds VALUES ($memberVal, $courseVal, '$(EscapeSql($datePlayed))', $totalVal, $puttsVal, $fairwaysVal, $girVal, N'$(EscapeSql($notes))'); SELECT id FROM @InsertedIds;"

            $res = Invoke-Sql -Server $ServerInstance -Database $DatabaseName -Query $q2
            if ($res.Count -gt 0) {
                $insertedId = $res[0].id
                $roundExtMap[$ext] = $insertedId
            }
        }
    }

    # 4) Holes (row-by-row: needs ext_round_id -> inserted round id mapping)
    $holesPath = Join-Path $CsvFolder 'holes.csv'
    if (Test-Path $holesPath) {
        $holes = Import-Csv $holesPath
        Write-Host "Importing holes: $($holes.Count) rows"
        foreach ($h in $holes) {
            $ext = $h.ext_round_id
            if (-not $ext) { Write-Warning "Hole row missing ext_round_id; skipping"; continue }
            if (-not $roundExtMap.ContainsKey($ext)) {
                Write-Warning "No round mapping found for ext_round_id '$ext'; skipping hole"; continue
            }
            $roundId = $roundExtMap[$ext]
            $holeNumber = if ($h.hole_number -ne '') { [int]$h.hole_number } else { $null }
            $par = if ($h.par -ne '') { [int]$h.par } else { $null }
            $strokes = if ($h.strokes -ne '') { [int]$h.strokes } else { $null }
            $putts = if ($h.putts -ne '') { [int]$h.putts } else { $null }
            $fairway_hit = if ($h.fairway_hit -ne '') { [int]$h.fairway_hit } else { $null }
            $gir = if ($h.gir -ne '') { [int]$h.gir } else { $null }

            $q3 = "INSERT INTO dbo.holes (round_id, hole_number, par, strokes, putts, fairway_hit, gir) VALUES ($roundId, $(if ($holeNumber -ne $null) { $holeNumber } else { 'NULL' }), $(if ($par -ne $null) { $par } else { 'NULL' }), $(if ($strokes -ne $null) { $strokes } else { 'NULL' }), $(if ($putts -ne $null) { $putts } else { 'NULL' }), $(if ($fairway_hit -ne $null) { $fairway_hit } else { 'NULL' }), $(if ($gir -ne $null) { $gir } else { 'NULL' }));"
            Invoke-Sql -Server $ServerInstance -Database $DatabaseName -Query $q3 | Out-Null
        }
    }

    Write-Host "Import complete."
}
catch {
    Write-Error "Error during import: $_"
    exit 1
}
