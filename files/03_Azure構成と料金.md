# Azure SQL Database 構成と料金

> ⚠️ 料金は変動が早く、地域（Japan East等）や為替でも変わる。
> 以下 §2〜§6 は検討時の「規模感」の記録。**実際に作成した構成は §0 を参照。**

---

## 0. 実際に作成した構成（2026-07-25）

### リソース

| 種別 | 名前 | 備考 |
|---|---|---|
| リソースグループ | `RailAngyer` | すべてここに集約。やめるときはグループごと削除 |
| 論理SQLサーバー | `railangyer` | 接続先: `railangyer.database.windows.net`。**名前は変更不可** |
| SQLデータベース | `RailAngyer` | 実データとコンピューティングの単位。課金もこちら |
| リージョン | Japan East | — |

> サーバーとデータベースが別リソースとして2つ並ぶのは正常。
> サーバーは「接続の入口＋ファイアウォール・認証・TLSの設定単位」で、それ自体には課金されない。

### 適用された無料オファー

**100,000 vCore秒 / データ 32GB / バックアップ 32GB を毎月、サブスクリプションの存続期間中。**

- 上限到達時の挙動: **Auto-pause the database until next month**（超過課金なし）
  - ⚠️ 上限に達すると**翌月1日までアクセス不能**になる。月途中で使い切るとその月は共有機能が使えない
- 無料オファーは**1サブスクリプションにつき1データベースまで**（開発用と本番用を分けられない）

### 構成

| 項目 | 設定 | 意図 |
|---|---|---|
| サービスレベル | 汎用目的 - サーバーレス Gen5 / 2 vCore | 使わない時間は課金されない。自動一時停止が前提 |
| ゾーン冗長 | 無効 | 有効にすると課金対象 |
| バックアップ冗長性 | ローカル冗長（LRS） | 最安。geo冗長は無料枠を超える可能性 |
| 認証 | SQL ＋ Microsoft Entra | Entra管理者を設定済み。パスワードを持ち歩かずに接続できる |
| SQL管理者 | `non` | **この資格情報はアプリ／APIに埋めない。専用ユーザーを別途作る** |
| 接続方法 | パブリックエンドポイント | プライベートエンドポイントはVNet必須・有料 |
| Azureサービスの許可 | いいえ | 他テナントのリソースからの経路を開けない。API層を建てる際に個別許可する |
| ファイアウォール | 自分のクライアントIPのみ | 移動したら都度追加が必要（下記） |
| 接続ポリシー | 既定 | 外部からはプロキシ（1433のみ）、Azure内からはリダイレクト |
| TLS 最小 | 1.2 | — |
| Advanced Data Security | 後で | **有効にすると Microsoft Defender for SQL が課金対象になる。無料構成を保つならこのまま** |
| 照合順序 | `SQL_Latin1_General_CP1_CI_AS`（既定） | 本アプリは並べ替えを OrderNo / 日時で行うため影響なし。**作成後は変更不可** |
| データソース | Blank | `06_schema.sql` を自分で流す |

### IPが変わったときの対処

ファイアウォールはIP許可制のため、作業場所を変えると接続できなくなる
（`Msg 40615: Client with IP address 'x.x.x.x' is not allowed to access the server.`）。

```bash
# ~/.zshrc に入れておく
sqlip() {
  local ip=$(curl -s ifconfig.me)
  az sql server firewall-rule create -g RailAngyer -s railangyer \
    -n "mac-$(date +%Y%m%d-%H%M)" --start-ip-address $ip --end-ip-address $ip
  echo "許可: $ip"
}
```

```bash
# 棚卸し（共有回線のIPを開けっぱなしにしない）
az sql server firewall-rule list   -g RailAngyer -s railangyer -o table
az sql server firewall-rule delete -g RailAngyer -s railangyer -n "mac-20260725-1430"
```

⚠️ `0.0.0.0`〜`255.255.255.255` の全開放規則は作らないこと。管理者ログイン名が既知の状態で全世界に開くことになる。

### 実施済み（2026-07-25）

- [x] **自動一時停止が有効**であることを確認
      （実際に `Paused` から復帰した。1回目の接続は必ず失敗し、再試行で繋がる）
- [x] **`06_schema.sql` を実行** — 10テーブル / PK 10 / FK 24 / CHECK 15 / UNIQUE 6 /
      フィルター付きインデックス `UX_Turn_Active` を作成。`Course` 1行 ＋ `Station` 16行を投入
- [x] **制約の動作確認**（トランザクションでロールバック済み）
      最大出目10・スタート=ゴール・効果なしなのに駅数あり・ジャンプ先なし・
      同一メンバーの同一駅2個目・進行中ターンの二重作成・ターン未紐付けの着地 …
      いずれも拒否されることを確認。同一駅の再訪は記録できることも確認
- [x] **アプリ／API用ユーザーの作成** → `09_アプリ用ユーザー.sql`
      ロール `app_railangyer` に必要な権限のみを付与し、包含ユーザー `railangyer_app` を作成。
      パスワードは macOS キーチェーンに格納（リポジトリには置かない）

### 接続方法

**管理者として（スキーマ変更・調査）** — パスワード不要。`az login` のトークンを使う。

```bash
sqlcmd -S railangyer.database.windows.net -d RailAngyer \
       --authentication-method ActiveDirectoryAzCli
```

> ⚠️ フラグは `ActiveDirectoryAzCli`。`ActiveDirectoryAzureCli` ではない。

**アプリ用ユーザーとして（動作確認）**

```bash
export SQLCMDPASSWORD=$(security find-generic-password -a railangyer_app -s RailAngyer -w)
sqlcmd -S railangyer.database.windows.net -d RailAngyer -U railangyer_app
unset SQLCMDPASSWORD
```

### 次の作業

- [ ] フェーズ2で App Service / Functions を建てたら、**マネージドIDに切り替える**
      （`09_アプリ用ユーザー.sql` §3.2。パスワード方式のユーザーはその時点で削除する）
- [ ] API層の送信元IPをファイアウォールに追加する

---

## 1. 結論（先に要点）

- 身内数人・小さいデータ量なら、**Azure SQL Database の無料枠 + Blob Storage** で、**月額ほぼ0円**で回せる見込み。
- 本業の .NET / C# / Azure / SQL Server の知見がそのまま活きるのが最大の利点。
- ただし Azure は各サービス（DB + Blob + 認証）を自分で組み合わせる必要があり、
  身内用の小さいアプリだと構成がやや大掛かりになりがち。
  「本業スキルで0円運用」を取るなら Azure、「最短で共有機能を立ち上げる」なら Supabase、というトレードオフ。

---

## 2. Azure SQL Database の無料オファー

Azure SQL Database には無料で使えるオファーが存在する（サーバーレス構成をベースにした無料枠）。

- 月あたり一定の **vCore 時間**（コンピュート）が無料
- 一定の **ストレージ（数百MB〜1GB程度）** が無料
- 上限に達したときの挙動を、作成時に選べる
  - 自動的に一時停止（それ以上課金しない）
  - もしくは通常課金に切り替え

### 身内アプリでの見込み
- データはテキスト中心で数百〜数千レコード程度 → ストレージ無料枠に十分収まる
- 利用は「時々みんなで遊ぶ」程度 → サーバーレスなので使わない時間は課金されにくい
- **無料枠内でおさまる可能性が高い**

> ⚠️ 無料オファーの内容（無料になる vCore 時間・ストレージ量・上限到達時の挙動）は
> 提供時期により変わる。作成前に「Azure SQL Database free offer」の最新条件を必ず確認。

---

## 3. 有料になった場合の目安（規模感）

無料枠を超えた場合のおおまかな水準。正確な数値ではなく規模感として。

| 構成 | 目安（月額） | 備考 |
|---|---|---|
| SQL Database サーバーレス（最小） | 数百円〜千円台〜 | 使った分だけ課金。時々遊ぶ用途なら安く抑えやすい |
| SQL Database Basic 相当 | 数百円〜千円台 | 固定の小容量プラン |
| Blob Storage（写真） | 数円〜数十円 | 写真数十〜数百枚ならごく僅か |

> ⚠️ 上記は概算。Japan East 等の実額は Pricing Calculator で要確認。

---

## 4. 推奨システム構成

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ 身内の端末A  │     │ 身内の端末B  │     │ 身内の端末C  │
│ (iOS/SwiftUI)│     │ (iOS/SwiftUI)│     │ (iOS/SwiftUI)│
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │  HTTPS
                  ┌────────▼─────────┐
                  │   API層(任意)     │  ← ASP.NET Core Web API
                  │  ※直接DB接続でも可 │     (本業スタック。App Serviceに配置)
                  └────────┬─────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
┌───────▼────────┐ ┌───────▼────────┐ ┌───────▼────────┐
│Azure SQL DB     │ │Blob Storage     │ │認証(Entra ID    │
│(ミッション/予定/ │ │(写真の実体)      │ │ /B2C など)      │
│ 記録)           │ │                 │ │※招待コードで代替可│
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

### 構成の選択肢
1. **API層あり（推奨・堅実）**: iOS ⇔ ASP.NET Core Web API ⇔ SQL DB。
   本業スタックそのまま。認証・バリデーションをAPIに集約でき安全。App Service にも無料/低額枠がある。
2. **API層なし（最小・手軽）**: iOSから直接DB接続、または軽量なサーバーレス関数（Azure Functions）経由。
   構成は減るが、接続情報の扱いに注意。身内用なら Functions 経由が現実的。

---

## 5. 認証について

「駅ごとに1人1個」「誰が作ったか」「誰が撮ったか」「予定の参加可否」を成立させるには、ゆるくてもユーザー識別が要る。
ただし身内用なので厳密なアカウント作成は重い。

- **招待コード方式（推奨・軽い）**: MissionSet ごとの InviteCode でルームに参加。
  メンバーは DisplayName を名乗るだけ。Entra ID / B2C を立てずに済む。
- **Entra ID / B2C（本格的）**: 将来一般公開するなら検討。身内用にはオーバースペック。

> ⚠️ ログインやアカウント作成の操作そのものは代行できない領域。実装時に自分で設定する。

---

## 6. Supabase との比較（再掲）

| 観点 | Azure SQL Database | Supabase |
|---|---|---|
| 学習コスト（あなた） | 低（本業スキル） | 中 |
| 認証・DB・ストレージ・同期の統合 | 各サービスを自分で組む | 最初から統合済み |
| 無料での運用 | 無料枠で0円見込み | 無料枠で0円見込み |
| SQLで考えられるか | ◎ | ◎(PostgreSQL) |
| 立ち上げの速さ | やや手間 | 速い |

**判断軸**: 本業スキルを活かして0円運用 → Azure。最短で共有機能を立ち上げ → Supabase。

---

## 7. 確認すべき公式ページ（次のアクション）

料金は変わりやすいので、着手前に以下を確認する。

- Azure SQL Database 料金ページ（azure.microsoft.com）
- Azure Free services / 無料オファー一覧
- Azure Pricing Calculator（Japan East 基準で試算）
- Blob Storage 料金ページ

> ブラウザ（Chrome拡張）を接続すれば、これらを一緒に開いて現時点の数字を確認できる。
