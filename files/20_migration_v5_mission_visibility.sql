/* ============================================================
   RailAngyer スキーマ移行 v5（2026-08-02）

   お題を「当日までのお楽しみ」にするか「いつでも見える」ようにするかを、
   **ルームごとに**選べるようにする。

   ・0 = 当日までのお楽しみ（既定。これまでの動き）
   ・1 = いつでも見える

   **サーバーが他人のお題を返すかどうかを決める値。**
   クライアントで隠すだけでは、通信を覗けば見えてしまう（`14_引き継ぎ.md` §4）。

   **何度実行しても安全**。すでに列があれば何もしない。

   実行方法（管理者として）
     sqlcmd -S railangyer.database.windows.net -d RailAngyer \
            --authentication-method ActiveDirectoryAzCli \
            -i files/20_migration_v5_mission_visibility.sql
   ============================================================ */

SET NOCOUNT ON;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.MissionSet') AND name = 'MissionVisibility')
BEGIN
    ALTER TABLE dbo.MissionSet
        ADD MissionVisibility TINYINT NOT NULL
            CONSTRAINT DF_MissionSet_MissionVisibility DEFAULT 0;

    PRINT 'dbo.MissionSet.MissionVisibility を追加しました';
END
ELSE
BEGIN
    PRINT 'dbo.MissionSet.MissionVisibility はすでにあります';
END
GO

/* 0か1しか入らないようにする。増えたときはこの制約も直す */
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID('dbo.MissionSet')
      AND name = 'CK_MissionSet_MissionVisibility')
BEGIN
    ALTER TABLE dbo.MissionSet
        ADD CONSTRAINT CK_MissionSet_MissionVisibility
            CHECK (MissionVisibility IN (0, 1));

    PRINT 'CK_MissionSet_MissionVisibility を追加しました';
END
GO

SELECT c.name AS 列, t.name AS 型, c.is_nullable AS NULL可
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.MissionSet') AND c.name = 'MissionVisibility';
GO
