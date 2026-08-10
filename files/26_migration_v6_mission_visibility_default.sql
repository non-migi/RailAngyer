/* お題の見え方の既定を「みんなに見える」へ変える（20_migration_v5_mission_visibility.sql の続き）。

   もともとは 0=当日までのお楽しみ を既定にしていたが、
   遊んでみると「書いたお題が誰にも見えない」と戸惑う声の方が多かった。
   これからは 1=いつでも見える が既定。伏せたい予定だけ、予定の詳細設定で 0 を選ぶ。

   既存ルームの 0 は「選んだ」のではなく旧既定のままなので、まとめて 1 に直す。 */

IF EXISTS (SELECT 1 FROM sys.default_constraints
           WHERE name = 'DF_MissionSet_MissionVisibility')
BEGIN
    ALTER TABLE dbo.MissionSet DROP CONSTRAINT DF_MissionSet_MissionVisibility;
    ALTER TABLE dbo.MissionSet ADD CONSTRAINT DF_MissionSet_MissionVisibility
        DEFAULT 1 FOR MissionVisibility;
    PRINT 'MissionVisibility の既定を 1（いつでも見える）にしました';
END
GO

UPDATE dbo.MissionSet SET MissionVisibility = 1 WHERE MissionVisibility = 0;
GO
