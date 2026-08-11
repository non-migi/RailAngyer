/* 予定に「お題への取り組み方」を追加する（25_migration_v5_schedule_detail.sql の続き）。

   これまではお題を1つ引いて全員で取り組む形だけだった。
   めいめいが自分のお題を引く遊び方を選べるようにする。

   既存予定と旧アプリのリクエストは NULL のままでよい。
   NULL は既定＝「みんなで1つ」（これまで通りの遊び方）とみなす。

   ⚠️ 個人モードの結果（誰がどのお題を引いて、どうなったか）は端末の中だけに持つ。
   Turn まわりのテーブルはこの移行では変えない。 */

IF COL_LENGTH('dbo.Schedule', 'MissionStyle') IS NULL
    ALTER TABLE dbo.Schedule ADD MissionStyle TINYINT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'IncludesOwnMissions') IS NULL
    ALTER TABLE dbo.Schedule ADD IncludesOwnMissions BIT NULL;
GO

IF OBJECT_ID('dbo.CK_Schedule_MissionStyle', 'C') IS NULL
    ALTER TABLE dbo.Schedule ADD CONSTRAINT CK_Schedule_MissionStyle
        /* 0=みんなで1つ 1=めいめいで */
        CHECK (MissionStyle IS NULL OR MissionStyle IN (0, 1));
GO
