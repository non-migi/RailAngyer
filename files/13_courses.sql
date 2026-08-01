/* ============================================================
   RailAngyer コース追加（フェーズ4）

   東西線・東豊線・山手線を投入する。
   **何度実行しても安全**（既にあるコースと駅は触らない）。

   札幌3路線の座標は国土交通省「国土数値情報 鉄道データ（N02-22）」
   の駅区間中央（JGD2011）。
   ⚠️ 山手線は環状だが、GameEngine が扱えるのは始点と終点のある区間だけなので、
      東京から順に並べた直線として入れてある（有楽町→東京の1区間ぶんが残る）。

   実行方法（管理者として）
     sqlcmd -S railangyer.database.windows.net -d RailAngyer \
            --authentication-method ActiveDirectoryAzCli \
            -i files/13_courses.sql
   ============================================================ */

SET NOCOUNT ON;
GO

/* ------------------------------------------------------------
   東西線（宮の沢 → 新さっぽろ、19駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'東西線')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'東西線', N'#F39700');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'東西線');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'宮の沢', 1, 43.089525, 141.277760),
    (N'発寒南', 2, 43.081530, 141.290220),
    (N'琴似', 3, 43.075445, 141.304445),
    (N'二十四軒', 4, 43.070450, 141.313605),
    (N'西28丁目', 5, 43.060965, 141.314565),
    (N'円山公園', 6, 43.055735, 141.319515),
    (N'西18丁目', 7, 43.057240, 141.330405),
    (N'西11丁目', 8, 43.058685, 141.341395),
    (N'大通', 9, 43.060083, 141.352253),
    (N'バスセンター前', 10, 43.061525, 141.361925),
    (N'菊水', 11, 43.057260, 141.372755),
    (N'東札幌', 12, 43.051793, 141.384720),
    (N'白石', 13, 43.046350, 141.395705),
    (N'南郷7丁目', 14, 43.040265, 141.410970),
    (N'南郷13丁目', 15, 43.035725, 141.422965),
    (N'南郷18丁目', 16, 43.030330, 141.435165),
    (N'大谷地', 17, 43.027930, 141.453145),
    (N'ひばりが丘', 18, 43.032105, 141.464470),
    (N'新さっぽろ', 19, 43.038930, 141.474015)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

/* ------------------------------------------------------------
   東豊線（栄町 → 福住、14駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'東豊線')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'東豊線', N'#0080C6');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'東豊線');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'栄町', 1, 43.113020, 141.367145),
    (N'新道東', 2, 43.104627, 141.369197),
    (N'元町', 3, 43.094040, 141.371785),
    (N'環状通東', 4, 43.082380, 141.374425),
    (N'東区役所前', 5, 43.078215, 141.365270),
    (N'北13条東', 6, 43.076825, 141.354935),
    (N'さっぽろ', 7, 43.066240, 141.353885),
    (N'大通', 8, 43.060687, 141.355317),
    (N'豊水すすきの', 9, 43.054095, 141.356990),
    (N'学園前', 10, 43.047710, 141.368955),
    (N'豊平公園', 11, 43.042110, 141.376165),
    (N'美園', 12, 43.036183, 141.385773),
    (N'月寒中央', 13, 43.029927, 141.396733),
    (N'福住', 14, 43.021825, 141.402885)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

/* ------------------------------------------------------------
   山手線（東京 → 有楽町、30駅）
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM dbo.Course WHERE Name = N'山手線')
BEGIN
    INSERT INTO dbo.Course (Name, LineColor) VALUES (N'山手線', N'#9ACD32');
END
GO

DECLARE @CourseId INT = (SELECT CourseId FROM dbo.Course WHERE Name = N'山手線');

INSERT INTO dbo.Station (CourseId, Name, OrderNo, Latitude, Longitude)
SELECT @CourseId, v.Name, v.OrderNo, v.Latitude, v.Longitude
FROM (VALUES
    (N'東京', 1, 35.6812, 139.7671),
    (N'神田', 2, 35.6918, 139.7708),
    (N'秋葉原', 3, 35.6984, 139.7731),
    (N'御徒町', 4, 35.7075, 139.7745),
    (N'上野', 5, 35.7138, 139.777),
    (N'鶯谷', 6, 35.7212, 139.7787),
    (N'日暮里', 7, 35.728, 139.771),
    (N'西日暮里', 8, 35.7322, 139.7669),
    (N'田端', 9, 35.738, 139.7608),
    (N'駒込', 10, 35.7365, 139.7469),
    (N'巣鴨', 11, 35.7334, 139.7393),
    (N'大塚', 12, 35.7312, 139.7286),
    (N'池袋', 13, 35.7295, 139.7109),
    (N'目白', 14, 35.7212, 139.7064),
    (N'高田馬場', 15, 35.7128, 139.7038),
    (N'新大久保', 16, 35.7013, 139.7),
    (N'新宿', 17, 35.69, 139.7004),
    (N'代々木', 18, 35.683, 139.702),
    (N'原宿', 19, 35.6702, 139.7027),
    (N'渋谷', 20, 35.658, 139.7016),
    (N'恵比寿', 21, 35.6467, 139.71),
    (N'目黒', 22, 35.6339, 139.7156),
    (N'五反田', 23, 35.6258, 139.7238),
    (N'大崎', 24, 35.6197, 139.7286),
    (N'品川', 25, 35.6285, 139.7387),
    (N'高輪ゲートウェイ', 26, 35.6357, 139.7404),
    (N'田町', 27, 35.6456, 139.7476),
    (N'浜松町', 28, 35.6553, 139.757),
    (N'新橋', 29, 35.6662, 139.7583),
    (N'有楽町', 30, 35.675, 139.763)
) AS v(Name, OrderNo, Latitude, Longitude)
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Station s WHERE s.CourseId = @CourseId AND s.OrderNo = v.OrderNo);
GO

/* ------------------------------------------------------------
   確認
   ------------------------------------------------------------ */
SELECT c.Name AS コース, COUNT(s.StationId) AS 駅数,
       MIN(s.OrderNo) AS 始点, MAX(s.OrderNo) AS 終点
FROM dbo.Course c LEFT JOIN dbo.Station s ON s.CourseId = c.CourseId
GROUP BY c.Name
ORDER BY c.Name;
GO
