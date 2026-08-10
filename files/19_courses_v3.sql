/* ============================================================
   RailAngyer コース追加（2026-08-01）

   ・阪急京都本線（28駅・大阪梅田 → 京都河原町）を追加する
     札幌・東京の外に出る最初のコース。**都道府県をまたぐ**（大阪府・京都府）

   座標は OpenStreetMap の駅ノード（© OpenStreetMap contributors / ODbL）。

   **何度実行しても安全**。JSONから生成しているので手写しのズレが入らない
   （正は `RailAngyerCore/Sources/RailAngyerCore/Resources/hankyu_kyoto.json`）。

   国・都道府県はアプリの一覧で使うだけなので、DBには持たせていない
   （環状・到着半径も同じ扱い。正はいずれもJSON）。

   実行方法（管理者として）
     sqlcmd -S railangyer.database.windows.net -d RailAngyer \
            --authentication-method ActiveDirectoryAzCli -i files/19_courses_v3.sql
   ============================================================ */

SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'阪急京都本線')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'阪急京都本線', N'#6C3524');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'阪急京都本線');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'大阪梅田',   1, 34.705419, 135.498372),
    (N'十三',     2, 34.720541, 135.482178),
    (N'南方',     3, 34.725665, 135.499707),
    (N'崇禅寺',    4, 34.730981, 135.510161),
    (N'淡路',     5, 34.739255, 135.516892),
    (N'上新庄',    6, 34.750273, 135.533055),
    (N'相川',     7, 34.757645, 135.533608),
    (N'正雀',     8, 34.775606, 135.545762),
    (N'摂津市',    9, 34.786754, 135.553937),
    (N'南茨木',   10, 34.802357, 135.565179),
    (N'茨木市',   11, 34.816666, 135.575840),
    (N'総持寺',   12, 34.826982, 135.584623),
    (N'富田',    13, 34.835116, 135.592599),
    (N'高槻市',   14, 34.849863, 135.623248),
    (N'上牧',    15, 34.872080, 135.661763),
    (N'水無瀬',   16, 34.877572, 135.667577),
    (N'大山崎',   17, 34.891441, 135.681624),
    (N'西山天王山', 18, 34.913190, 135.688584),
    (N'長岡天神',  19, 34.925358, 135.692709),
    (N'西向日',   20, 34.940520, 135.703216),
    (N'東向日',   21, 34.953587, 135.704734),
    (N'洛西口',   22, 34.963803, 135.703193),
    (N'桂',     23, 34.979432, 135.703261),
    (N'西京極',   24, 34.992478, 135.718365),
    (N'西院',    25, 35.003566, 135.731766),
    (N'大宮',    26, 35.003644, 135.748588),
    (N'烏丸',    27, 35.003686, 135.760452),
    (N'京都河原町', 28, 35.003763, 135.769608)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

SELECT c.Name AS コース, COUNT(s.StationId) AS 駅数
FROM dbo.Course c LEFT JOIN dbo.Station s ON s.CourseId = c.CourseId
GROUP BY c.Name ORDER BY c.Name;
GO
