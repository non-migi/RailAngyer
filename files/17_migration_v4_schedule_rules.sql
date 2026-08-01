/* 予定に、その日に使うルールセットのスナップショットを追加する。
   既存予定と旧アプリのリクエストは NULL のままでも利用できる。 */

IF COL_LENGTH('dbo.Schedule', 'CourseId') IS NULL
    ALTER TABLE dbo.Schedule ADD CourseId INT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'CourseName') IS NULL
    ALTER TABLE dbo.Schedule ADD CourseName NVARCHAR(50) NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'StartOrder') IS NULL
    ALTER TABLE dbo.Schedule ADD StartOrder INT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'GoalOrder') IS NULL
    ALTER TABLE dbo.Schedule ADD GoalOrder INT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'DiceMax') IS NULL
    ALTER TABLE dbo.Schedule ADD DiceMax TINYINT NULL;
GO

IF OBJECT_ID('dbo.CK_Schedule_Dice', 'C') IS NULL
    ALTER TABLE dbo.Schedule ADD CONSTRAINT CK_Schedule_Dice
        CHECK (DiceMax IS NULL OR DiceMax BETWEEN 1 AND 9);
GO
IF OBJECT_ID('dbo.CK_Schedule_Section', 'C') IS NULL
    ALTER TABLE dbo.Schedule ADD CONSTRAINT CK_Schedule_Section
        CHECK (StartOrder IS NULL OR GoalOrder IS NULL OR StartOrder <> GoalOrder);
GO

/* 札幌市営地下鉄3路線を国土数値情報 N02-22（JGD2011）の位置へ補正する。 */
UPDATE s
SET s.Latitude = v.Latitude,
    s.Longitude = v.Longitude
FROM dbo.Station s
JOIN dbo.Course c ON c.CourseId = s.CourseId
JOIN (VALUES
    (N'南北線', 1, 43.108340, 141.338480),
    (N'南北線', 2, 43.100105, 141.342130),
    (N'南北線', 3, 43.089610, 141.344825),
    (N'南北線', 4, 43.081645, 141.346755),
    (N'南北線', 5, 43.074700, 141.348495),
    (N'南北線', 6, 43.065860, 141.350665),
    (N'南北線', 7, 43.060027, 141.352137),
    (N'南北線', 8, 43.055300, 141.353365),
    (N'南北線', 9, 43.048475, 141.355055),
    (N'南北線', 10, 43.040220, 141.355835),
    (N'南北線', 11, 43.037450, 141.361195),
    (N'南北線', 12, 43.034620, 141.368370),
    (N'南北線', 13, 43.026660, 141.371343),
    (N'南北線', 14, 43.016825, 141.367360),
    (N'南北線', 15, 43.006005, 141.364915),
    (N'南北線', 16, 42.991180, 141.358545),
    (N'東西線', 1, 43.089525, 141.277760),
    (N'東西線', 2, 43.081530, 141.290220),
    (N'東西線', 3, 43.075445, 141.304445),
    (N'東西線', 4, 43.070450, 141.313605),
    (N'東西線', 5, 43.060965, 141.314565),
    (N'東西線', 6, 43.055735, 141.319515),
    (N'東西線', 7, 43.057240, 141.330405),
    (N'東西線', 8, 43.058685, 141.341395),
    (N'東西線', 9, 43.060083, 141.352253),
    (N'東西線', 10, 43.061525, 141.361925),
    (N'東西線', 11, 43.057260, 141.372755),
    (N'東西線', 12, 43.051793, 141.384720),
    (N'東西線', 13, 43.046350, 141.395705),
    (N'東西線', 14, 43.040265, 141.410970),
    (N'東西線', 15, 43.035725, 141.422965),
    (N'東西線', 16, 43.030330, 141.435165),
    (N'東西線', 17, 43.027930, 141.453145),
    (N'東西線', 18, 43.032105, 141.464470),
    (N'東西線', 19, 43.038930, 141.474015),
    (N'東豊線', 1, 43.113020, 141.367145),
    (N'東豊線', 2, 43.104627, 141.369197),
    (N'東豊線', 3, 43.094040, 141.371785),
    (N'東豊線', 4, 43.082380, 141.374425),
    (N'東豊線', 5, 43.078215, 141.365270),
    (N'東豊線', 6, 43.076825, 141.354935),
    (N'東豊線', 7, 43.066240, 141.353885),
    (N'東豊線', 8, 43.060687, 141.355317),
    (N'東豊線', 9, 43.054095, 141.356990),
    (N'東豊線', 10, 43.047710, 141.368955),
    (N'東豊線', 11, 43.042110, 141.376165),
    (N'東豊線', 12, 43.036183, 141.385773),
    (N'東豊線', 13, 43.029927, 141.396733),
    (N'東豊線', 14, 43.021825, 141.402885)
) v(CourseName, OrderNo, Latitude, Longitude)
    ON v.CourseName = c.Name AND v.OrderNo = s.OrderNo;
GO
