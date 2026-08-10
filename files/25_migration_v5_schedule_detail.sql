/* 予定の「詳細設定」を追加する（17_migration_v4_schedule_rules.sql の続き）。

   ルール設定はルームではなく予定に紐づくようになった。
   サイコロもお題も任意で、両方なしの「そのまま歩くだけ」も成り立つ。

   既存予定と旧アプリのリクエストは NULL のままでよい。
   NULL は「これまで通りの遊び方」（サイコロあり・お題あり・全員に見える・共有オン）とみなす。 */

IF COL_LENGTH('dbo.Schedule', 'IsLap') IS NULL
    ALTER TABLE dbo.Schedule ADD IsLap BIT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'LoopDirection') IS NULL
    ALTER TABLE dbo.Schedule ADD LoopDirection SMALLINT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'UsesDice') IS NULL
    ALTER TABLE dbo.Schedule ADD UsesDice BIT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'UsesMissions') IS NULL
    ALTER TABLE dbo.Schedule ADD UsesMissions BIT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'MissionVisibility') IS NULL
    ALTER TABLE dbo.Schedule ADD MissionVisibility TINYINT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'ArrivalRadius') IS NULL
    ALTER TABLE dbo.Schedule ADD ArrivalRadius FLOAT NULL;
GO
IF COL_LENGTH('dbo.Schedule', 'IsShared') IS NULL
    ALTER TABLE dbo.Schedule ADD IsShared BIT NULL;
GO
/* 集合日時をどの土地の時計で読むか（例 Asia/Tokyo）。NULL は日本時間。
   IANA のタイムゾーン名がいちばん長いもので 32 文字ほどなので 64 で足りる。 */
IF COL_LENGTH('dbo.Schedule', 'TimeZoneId') IS NULL
    ALTER TABLE dbo.Schedule ADD TimeZoneId NVARCHAR(64) NULL;
GO

IF OBJECT_ID('dbo.CK_Schedule_LoopDirection', 'C') IS NULL
    ALTER TABLE dbo.Schedule ADD CONSTRAINT CK_Schedule_LoopDirection
        CHECK (LoopDirection IS NULL OR LoopDirection IN (1, -1));
GO
IF OBJECT_ID('dbo.CK_Schedule_MissionVisibility', 'C') IS NULL
    ALTER TABLE dbo.Schedule ADD CONSTRAINT CK_Schedule_MissionVisibility
        CHECK (MissionVisibility IS NULL OR MissionVisibility IN (0, 1));
GO
IF OBJECT_ID('dbo.CK_Schedule_ArrivalRadius', 'C') IS NULL
    ALTER TABLE dbo.Schedule ADD CONSTRAINT CK_Schedule_ArrivalRadius
        /* ArrivalRule.radiusRange（50〜320m）と同じ範囲。
           上限は最短駅間（南北線 大通〜すすきの 約655m）の半分を超えない値 */
        CHECK (ArrivalRadius IS NULL OR ArrivalRadius BETWEEN 50 AND 320);
GO

/* 一周する予定は、スタートとゴールが同じ駅になるのが正しい。
   v4 の CK_Schedule_Section はそれを弾いてしまうので、IsLap のときだけ通す形に置き換える。 */
IF OBJECT_ID('dbo.CK_Schedule_Section', 'C') IS NOT NULL
    ALTER TABLE dbo.Schedule DROP CONSTRAINT CK_Schedule_Section;
GO
IF OBJECT_ID('dbo.CK_Schedule_Section', 'C') IS NULL
    ALTER TABLE dbo.Schedule ADD CONSTRAINT CK_Schedule_Section
        CHECK (IsLap = 1
               OR StartOrder IS NULL OR GoalOrder IS NULL
               OR StartOrder <> GoalOrder);
GO
