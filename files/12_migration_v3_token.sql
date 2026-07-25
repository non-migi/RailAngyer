/* ============================================================
   RailAngyer スキーマ移行 v2 → v3
   メンバートークン（11_API設計.md §2 / G-5 なりすまし対策）

   ⚠️ このスクリプトはまだ Azure に適用していない。
      フェーズ2の実装に入るときに、下記を確認してから実行すること。

   実行方法（管理者として）
     sqlcmd -S railangyer.database.windows.net -d RailAngyer \
            --authentication-method ActiveDirectoryAzCli \
            -i files/12_migration_v3_token.sql

   何を変えるか
     Member に TokenHash を足すだけ。既存のデータは壊れない。
     参加時に発行したトークンの SHA-256 を入れ、リクエストの MemberId を信用せずに
     本人を引くために使う。平文のトークンはDBにもリポジトリにも置かない。
   ============================================================ */

/* ------------------------------------------------------------
   1. 列の追加（何度実行しても安全）
   ------------------------------------------------------------ */
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.Member') AND name = 'TokenHash')
BEGIN
    ALTER TABLE dbo.Member ADD TokenHash BINARY(32) NULL;
END
GO

/* ------------------------------------------------------------
   2. 一意インデックス
   トークンの衝突を防ぐ。NULL（まだ発行していないメンバー）は対象外にするため
   フィルター選択されたインデックスにする
   ------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Member_TokenHash')
BEGIN
    CREATE UNIQUE INDEX UX_Member_TokenHash
        ON dbo.Member (TokenHash)
        WHERE TokenHash IS NOT NULL;
END
GO

/* ------------------------------------------------------------
   3. 確認
   ------------------------------------------------------------ */
/*
SELECT c.name, t.name AS TypeName, c.max_length, c.is_nullable
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.Member');

SELECT name, has_filter, filter_definition
FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Member');
*/

/* ------------------------------------------------------------
   4. 元に戻す場合
   ------------------------------------------------------------ */
/*
DROP INDEX UX_Member_TokenHash ON dbo.Member;
ALTER TABLE dbo.Member DROP COLUMN TokenHash;
*/
