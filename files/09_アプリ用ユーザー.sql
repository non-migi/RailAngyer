/* ============================================================
   RailAngyer
   アプリ／API層が使う最小権限ユーザーの定義

   方針
     - サーバー管理者（non）の資格情報は、アプリにもAPIにも絶対に置かない
     - 権限は「ロール」に付け、ユーザーはロールに入れるだけにする
       → 将来 App Service / Functions のマネージドIDを使うようになっても、
         同じロールに追加するだけで済む
     - DDL（テーブル作成・変更・削除）の権限は与えない
       スキーマ変更は管理者が 06_schema.sql で行う

   実行方法（管理者として接続して実行）
     sqlcmd -S railangyer.database.windows.net -d RailAngyer \
            --authentication-method ActiveDirectoryAzCli \
            -i files/09_アプリ用ユーザー.sql
   ============================================================ */


/* ------------------------------------------------------------
   1. ロールの作成
   ------------------------------------------------------------ */
IF DATABASE_PRINCIPAL_ID('app_railangyer') IS NULL
    CREATE ROLE app_railangyer;
GO


/* ------------------------------------------------------------
   2. 権限の付与

   テーブルごとに、アプリが実際に行う操作だけを許可する。
   「なぜその権限が要るか」を画面仕様のIDで示す。
   ------------------------------------------------------------ */

/* --- マスタ：参照のみ。アプリからは書き換えない --- */
GRANT SELECT ON dbo.Course  TO app_railangyer;   -- 盤面の路線情報
GRANT SELECT ON dbo.Station TO app_railangyer;   -- 駅・座標・並び順（SC-04 / SC-07）

/* --- ルーム：作成と設定。削除は管理者作業 --- */
GRANT SELECT, INSERT, UPDATE ON dbo.MissionSet TO app_railangyer;  -- SC-02 ルーム作成・CreatedBy の更新
GRANT SELECT, INSERT, UPDATE ON dbo.Member     TO app_railangyer;  -- SC-03 参加・表示名の変更

/* --- ミッション：作成・差し替え・削除 --- */
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Mission TO app_railangyer;  -- SC-12 編集シート

/* --- 予定：作成・更新・削除 --- */
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Schedule         TO app_railangyer;  -- SC-15
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.ScheduleAttendee TO app_railangyer;  -- SC-16 出欠

/* --- 進行記録：作成・更新・削除（記録リセット用） --- */
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.Turn TO app_railangyer;
    -- INSERT: F-01 サイコロを振る / UPDATE: F-06,F-08,F-10 / DELETE: SC-20 記録リセット

/* --- 訪問：追記と削除のみ。UPDATE は与えない --- */
GRANT SELECT, INSERT, DELETE ON dbo.Visit TO app_railangyer;
    -- 訪問記録は一度書いたら書き換えない設計のため UPDATE は不要。
    -- 誤った到着を「なかったこと」にするのは DELETE で行う。

/* --- 写真：追記と削除のみ --- */
GRANT SELECT, INSERT, DELETE ON dbo.Photo TO app_railangyer;
GO


/* ------------------------------------------------------------
   3. ユーザーの作成

   3.1 SQL認証の包含ユーザー（パスワード方式）  ★作成済み: 2026-07-25
       サーバーログインを作らず、このDBの中だけに存在するユーザー。
       接続文字列には必ず Database=RailAngyer を含めること。

       ユーザー名: railangyer_app
       パスワード: 32文字のランダム文字列を生成し、macOS キーチェーンに格納済み。
                   このファイルにもリポジトリにも書かない。

       取り出し方:
         security find-generic-password -a railangyer_app -s RailAngyer -w

       接続例（環境変数経由。パスワードをコマンドラインに出さない）:
         export SQLCMDPASSWORD=$(security find-generic-password -a railangyer_app -s RailAngyer -w)
         sqlcmd -S railangyer.database.windows.net -d RailAngyer -U railangyer_app
         unset SQLCMDPASSWORD

       ⚠️ パスワードを変更する場合:
         ALTER USER railangyer_app WITH PASSWORD = '<新しい値>';
         その後キーチェーンも更新する
           security add-generic-password -a railangyer_app -s RailAngyer -w '<新しい値>' -U
   ------------------------------------------------------------ */
/*
CREATE USER railangyer_app WITH PASSWORD = '<ここに強いパスワード>';
ALTER ROLE app_railangyer ADD MEMBER railangyer_app;
*/

/* ------------------------------------------------------------
   3.1.1 動作確認の結果（2026-07-25 実施）

     ✔ dbo.Station の SELECT          → 16件取得できる
     ✘ dbo.Station への INSERT        → Msg 229 権限がありません
     ✘ CREATE TABLE                   → Msg 262 権限がありません
     ✘ dbo.Visit の UPDATE            → Msg 229 権限がありません（設計どおり）
     ✔ dbo.Turn の UPDATE             → 実行できる

   「読めるが、スキーマもマスタも壊せない」状態になっていることを確認済み。
   ------------------------------------------------------------ */

/* ------------------------------------------------------------
   3.2 将来やること：マネージドIDに切り替える（推奨）

       App Service / Functions を建てたらシステム割り当てマネージドIDを有効にし、
       そのIDをこのDBのユーザーとして登録して同じロールに入れる。
       パスワードが一切不要になり、接続文字列から資格情報が消える。

       ※ 実行には Microsoft Entra 認証で接続している必要がある
   ------------------------------------------------------------ */
/*
CREATE USER [<App Service のリソース名>] FROM EXTERNAL PROVIDER;
ALTER ROLE app_railangyer ADD MEMBER [<App Service のリソース名>];

-- 切り替えが済んだらパスワード方式のユーザーは削除する
-- DROP USER railangyer_app;
*/


/* ------------------------------------------------------------
   4. 確認
   ------------------------------------------------------------ */
/*
-- ロールに付いている権限の一覧
SELECT o.name AS TableName, p.permission_name, p.state_desc
FROM sys.database_permissions p
JOIN sys.objects o ON o.object_id = p.major_id
WHERE p.grantee_principal_id = DATABASE_PRINCIPAL_ID('app_railangyer')
ORDER BY o.name, p.permission_name;

-- ロールの所属メンバー
SELECT m.name AS MemberName
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE r.name = 'app_railangyer';
*/
