/* ============================================================
   RailAngyer コース追加（2026-08-04・その3）

   ・大阪環状線（19駅・環状）           直線20.7km（営業キロ21.7km）
   ・ニューヨーク 7号線（22駅）         直線15.9km
   ・ロサンゼルス Eライン（29駅）       直線34.7km

   **大阪環状線は山手線の次に歩かれている環状線**（note の記録が多数）。
   実際に歩くと35km前後になる。

   ニューヨーク7号線はクイーンズ側が高架で線路沿いを歩ける。
   ロサンゼルス Eライン はダウンタウンからサンタモニカの海まで。

   座標と並び順は OpenStreetMap の路線リレーション
   （© OpenStreetMap contributors / ODbL）。

   **何度実行しても安全**。

   実行方法（管理者として）
     sqlcmd -S railangyer.database.windows.net -d RailAngyer \
            --authentication-method ActiveDirectoryAzCli -i files/24_courses_v6.sql
   ============================================================ */

SET NOCOUNT ON;
GO

/* ------------------------------------------------------------
   大阪環状線（天王寺から一周、19駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'大阪環状線')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'大阪環状線', N'#F8B500');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'大阪環状線');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'天王寺',      1, 34.647129, 135.514313),
    (N'新今宮',      2, 34.649743, 135.502168),
    (N'今宮',        3, 34.653957, 135.492893),
    (N'芦原橋',      4, 34.658685, 135.489147),
    (N'大正',        5, 34.665424, 135.480328),
    (N'弁天町',      6, 34.670276, 135.461809),
    (N'西九条',      7, 34.682874, 135.466799),
    (N'野田',        8, 34.689128, 135.474957),
    (N'福島',        9, 34.697310, 135.486806),
    (N'大阪',       10, 34.701999, 135.495750),
    (N'天満',       11, 34.704960, 135.512349),
    (N'桜ノ宮',     12, 34.704857, 135.520284),
    (N'京橋',       13, 34.696735, 135.534016),
    (N'大阪城公園', 14, 34.687754, 135.534426),
    (N'森ノ宮',     15, 34.680450, 135.534025),
    (N'玉造',       16, 34.673204, 135.532882),
    (N'鶴橋',       17, 34.665403, 135.530232),
    (N'桃谷',       18, 34.658749, 135.528081),
    (N'寺田町',     19, 34.647753, 135.523335)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

/* ------------------------------------------------------------
   ニューヨーク 7号線（34th St–Hudson Yards → Flushing、22駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'ニューヨーク 7号線')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'ニューヨーク 7号線', N'#B933AD');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'ニューヨーク 7号線');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'34th Street–Hudson Yards',         1, 40.755884, -74.001829),
    (N'Times Square–42nd Street',         2, 40.755092, -73.986847),
    (N'5th Avenue',                       3, 40.753354, -73.981002),
    (N'Grand Central–42nd Street',        4, 40.751052, -73.975219),
    (N'Vernon Boulevard–Jackson Avenue',  5, 40.742400, -73.952426),
    (N'Hunters Point Avenue',             6, 40.742447, -73.947883),
    (N'Court Square',                     7, 40.747788, -73.944981),
    (N'Queensboro Plaza',                 8, 40.750235, -73.939499),
    (N'33rd Street–Rawson Street',        9, 40.744437, -73.929977),
    (N'40th Street–Lowery Street',       10, 40.743633, -73.923006),
    (N'46th Street–Bliss Street',        11, 40.742982, -73.917403),
    (N'52nd Street–Lincoln Avenue',      12, 40.744399, -73.911649),
    (N'61st Street–Woodside',            13, 40.745672, -73.901962),
    (N'69th Street',                     14, 40.746399, -73.895406),
    (N'74th Street–Broadway',            15, 40.746930, -73.890368),
    (N'82nd Street–Jackson Heights',     16, 40.747728, -73.882770),
    (N'90th Street–Elmhurst Avenue',     17, 40.748474, -73.875671),
    (N'Junction Boulevard',              18, 40.749187, -73.868567),
    (N'103rd Street–Corona Plaza',       19, 40.749944, -73.861661),
    (N'111th Street',                    20, 40.751956, -73.854390),
    (N'Mets–Willets Point',              21, 40.754836, -73.844596),
    (N'Flushing–Main Street',            22, 40.759891, -73.829108)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

/* ------------------------------------------------------------
   ロサンゼルス Eライン（Downtown Santa Monica → Atlantic、29駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'ロサンゼルス Eライン')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'ロサンゼルス Eライン', N'#0072BC');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'ロサンゼルス Eライン');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'Downtown Santa Monica',          1, 34.013748, -118.491578),
    (N'17th Street/SMC',                2, 34.023351, -118.480095),
    (N'26th Street/Bergamot',           3, 34.028102, -118.468763),
    (N'Expo/Bundy',                     4, 34.031741, -118.452498),
    (N'Expo/Sepulveda',                 5, 34.035428, -118.433816),
    (N'Westwood/Rancho Park',           6, 34.036843, -118.424139),
    (N'Palms',                          7, 34.029241, -118.403874),
    (N'Culver City',                    8, 34.027800, -118.388463),
    (N'La Cienega/Jefferson',           9, 34.026283, -118.371694),
    (N'Expo/La Brea',                  10, 34.024728, -118.354751),
    (N'Farmdale',                      11, 34.023962, -118.346366),
    (N'Expo/Crenshaw',                 12, 34.022656, -118.335909),
    (N'Expo/Western',                  13, 34.018300, -118.307462),
    (N'Expo/Vermont',                  14, 34.018226, -118.290413),
    (N'Expo Park/USC',                 15, 34.018218, -118.285700),
    (N'Jefferson/USC',                 16, 34.022401, -118.277924),
    (N'LATTC/Ortho Institute',         17, 34.029450, -118.273341),
    (N'Pico',                          18, 34.040852, -118.265978),
    (N'7th Street/Metro Center',       19, 34.049097, -118.258288),
    (N'Grand Avenue Arts/Bunker Hill', 20, 34.054650, -118.251764),
    (N'Historic Broadway',             21, 34.052227, -118.246392),
    (N'Little Tokyo/Arts District',    22, 34.048884, -118.238549),
    (N'Pico/Aliso',                    23, 34.047584, -118.225589),
    (N'Mariachi Plaza',                24, 34.047139, -118.219047),
    (N'Soto',                          25, 34.043680, -118.209871),
    (N'Indiana',                       26, 34.033901, -118.192207),
    (N'Maravilla',                     27, 34.033271, -118.167600),
    (N'East LA Civic Center',          28, 34.033339, -118.160644),
    (N'Atlantic',                      29, 34.033363, -118.154037)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

SELECT c.Name AS コース, COUNT(s.StationId) AS 駅数
FROM dbo.Course c LEFT JOIN dbo.Station s ON s.CourseId = c.CourseId
GROUP BY c.Name ORDER BY c.Name;
GO
