/* 退室と除名のために、アプリ用ロールへ dbo.Member の DELETE を足す。

   退室（DELETE /rooms/{id}/members/me）と除名（同 /members/{memberId}）は、
   最後に Member 行そのものを消す。TokenHash ごと消すことで、発行済みトークンを
   その場で無効にするため（09_アプリ用ユーザー.sql の設計どおり最小権限で運用しており、
   Member には SELECT / INSERT / UPDATE しか与えていなかった）。

   **この穴はテストでは見つからない。** テストは SQLite で権限の仕組みが無く、
   本番の SQL Server でだけ「DELETE permission was denied on the object 'Member'」
   （エラー229）になり、API は 400 invalid_reference を返していた。

   他のテーブルは足りている:
     Photo / Mission / ScheduleAttendee … DELETE 付与済み
     Turn / Schedule / MissionSet       … 参照を外すだけなので UPDATE で足りる

   何度実行しても安全。 */

GRANT DELETE ON dbo.Member TO app_railangyer;
GO

/* 確認: 5行（SELECT / INSERT / UPDATE / DELETE / REFERENCES など）に DELETE が含まれること */
SELECT pe.permission_name
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
WHERE pr.name = 'app_railangyer'
  AND pe.major_id = OBJECT_ID('dbo.Member')
ORDER BY pe.permission_name;
GO
