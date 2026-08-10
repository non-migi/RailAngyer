/* ============================================================
   RailAngyer コース追加（2026-08-04）

   ・ベルリン Ringbahn（27駅・環状）
   ・ロンドン サークル線（27駅・環状）

   **日本の外に出る最初のコース。** どちらも山手線と同じく
   「環状の都市鉄道を1日で歩いて一周できる」路線で、
   内回り／外回りにあたる呼び分けも実在する（S41/S42、時計回り/反時計回り）。

   座標と並び順は OpenStreetMap の路線リレーション
   （© OpenStreetMap contributors / ODbL）。
   直線距離の合計は Ringbahn 35.4km（営業キロ37.5km）、
   サークル線 20.0km（Inner Circle 約21km）で、いずれもよく合う。

   国・都道府県・環状・到着半径はアプリの一覧で使うだけなので、
   DBには持たせていない（正はJSON）。

   **何度実行しても安全**。JSONから生成しているので手写しのズレが入らない。

   実行方法（管理者として）
     sqlcmd -S railangyer.database.windows.net -d RailAngyer \
            --authentication-method ActiveDirectoryAzCli -i files/22_courses_v4.sql
   ============================================================ */

SET NOCOUNT ON;
GO

/* ------------------------------------------------------------
   ベルリン Ringbahn（Gesundbrunnen から一周、27駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'ベルリン Ringbahn')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'ベルリン Ringbahn', N'#C4022E');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'ベルリン Ringbahn');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'Gesundbrunnen',        1, 52.549159, 13.389995),
    (N'Schönhauser Allee',    2, 52.548952, 13.416411),
    (N'Prenzlauer Allee',     3, 52.544610, 13.426242),
    (N'Greifswalder Straße',  4, 52.539862, 13.439659),
    (N'Landsberger Allee',    5, 52.528892, 13.455268),
    (N'Storkower Straße',     6, 52.523516, 13.465654),
    (N'Frankfurter Allee',    7, 52.514577, 13.474704),
    (N'Ostkreuz',             8, 52.502743, 13.468775),
    (N'Treptower Park',       9, 52.493408, 13.461174),
    (N'Sonnenallee',         10, 52.472538, 13.455168),
    (N'Neukölln',            11, 52.469378, 13.442366),
    (N'Hermannstraße',       12, 52.467568, 13.430352),
    (N'Tempelhof',           13, 52.471232, 13.383518),
    (N'Südkreuz',            14, 52.476335, 13.365338),
    (N'Schöneberg',          15, 52.479217, 13.350920),
    (N'Innsbrucker Platz',   16, 52.478168, 13.340659),
    (N'Bundesplatz',         17, 52.477702, 13.328961),
    (N'Heidelberger Platz',  18, 52.480452, 13.311339),
    (N'Hohenzollerndamm',    19, 52.488934, 13.299956),
    (N'Halensee',            20, 52.496014, 13.290687),
    (N'Westkreuz',           21, 52.501381, 13.283544),
    (N'Messe Nord/ZOB',      22, 52.508170, 13.283939),
    (N'Westend',             23, 52.518770, 13.284310),
    (N'Jungfernheide',       24, 52.530473, 13.300288),
    (N'Beusselstraße',       25, 52.534418, 13.330002),
    (N'Westhafen',           26, 52.536287, 13.344944),
    (N'Wedding',             27, 52.543321, 13.368339)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

/* ------------------------------------------------------------
   ロンドン サークル線（Paddington から一周、27駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'ロンドン サークル線')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'ロンドン サークル線', N'#FFD300');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'ロンドン サークル線');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'Paddington',               1, 51.515404, -0.175450),
    (N'Bayswater',                2, 51.512273, -0.188244),
    (N'Notting Hill Gate',        3, 51.508709, -0.195975),
    (N'High Street Kensington',   4, 51.500192, -0.191863),
    (N'Gloucester Road',          5, 51.494537, -0.183048),
    (N'South Kensington',         6, 51.494123, -0.172017),
    (N'Sloane Square',            7, 51.492174, -0.155548),
    (N'Victoria',                 8, 51.496355, -0.144098),
    (N'St. James''s Park',         9, 51.499429, -0.134173),
    (N'Westminster',             10, 51.501682, -0.124378),
    (N'Embankment',              11, 51.507293, -0.122373),
    (N'Temple',                  12, 51.511016, -0.114297),
    (N'Blackfriars',             13, 51.511655, -0.103563),
    (N'Mansion House',           14, 51.511929, -0.095226),
    (N'Cannon Street',           15, 51.511507, -0.090302),
    (N'Monument',                16, 51.510715, -0.086025),
    (N'Tower Hill',              17, 51.509872, -0.076637),
    (N'Aldgate',                 18, 51.514210, -0.075823),
    (N'Liverpool Street',        19, 51.517184, -0.082555),
    (N'Moorgate',                20, 51.518707, -0.090854),
    (N'Barbican',                21, 51.520203, -0.098730),
    (N'Farringdon',              22, 51.520819, -0.105255),
    (N'King''s Cross St Pancras', 23, 51.529592, -0.124545),
    (N'Euston Square',           24, 51.525828, -0.135137),
    (N'Great Portland Street',   25, 51.523798, -0.143869),
    (N'Baker Street',            26, 51.522259, -0.156650),
    (N'Edgware Road',            27, 51.520100, -0.166663)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

SELECT c.Name AS コース, COUNT(s.StationId) AS 駅数
FROM dbo.Course c LEFT JOIN dbo.Station s ON s.CourseId = c.CourseId
GROUP BY c.Name ORDER BY c.Name;
GO
