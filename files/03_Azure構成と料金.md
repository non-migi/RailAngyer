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

### 追加したリソース（2026-07-26）

| 種別 | 名前 | リージョン | 備考 |
|---|---|---|---|
| ストレージアカウント | `railangyer` | Japan East | 写真用。コンテナ `photos`（**非公開**）。**ローカル冗長（LRS）** |
| App Service プラン | `railangyer-plan-japanwest` | **Japan West** | Linux / **F1（無料）** |
| Web アプリ | `railangyer` | Japan West | `https://railangyer.azurewebsites.net` |

> ⚠️ **App Service が Japan West にあるのは、Japan East の VM 枠が 0 だったため。**
> `az appservice plan create --sku F1 --location japaneast` は
> `Operation cannot be completed without additional quota (Current Limit: 0)` で失敗する。
> Japan West / East Asia / Korea Central / Southeast Asia では作成できた。
> DB（Japan East）とは別リージョンになるが、国内同士なので往復は数ミリ秒。
> Japan East に寄せたい場合はサポートに枠の引き上げを申請する。

**F1（無料）の制約** — 身内用なら実害はないが、把握しておく。

| 項目 | 制約 |
|---|---|
| CPU | 1日あたり60分のCPU時間（超えると翌日までアプリが止まる） |
| Always On | 使えない。**一定時間アクセスが無いとアプリが寝る**（初回リクエストが遅い） |
| スケールアウト | 不可（1インスタンス固定） |
| 独自ドメイン・SSL | 不可（`*.azurewebsites.net` のみ） |

> DBの自動一時停止と合わせて、**アプリもDBも寝ている状態からの初回リクエストは分単位でかかりうる**。
> クライアントが起動時に `/health` を投げておく設計（`11_API設計.md`）はこのため。

> 💡 ストレージは既定の `Standard_RAGRS`（読み取りアクセス geo 冗長）で作られたが、
> 身内の写真置き場には過剰（LRS の約2倍の単価）なため **`Standard_LRS` に変更した**。
> DB のバックアップ冗長性を LRS にしているのと同じ判断。
>
> ```bash
> az storage account update -n railangyer -g RailAngyer --sku Standard_LRS
> ```
>
> ⚠️ LRS は**単一データセンター内の3重化**。リージョン規模の障害では失われる。
> 写真は端末側にも残る設計（`10_アプリ設計.md`）なので、これで許容する。
> 戻すときは同じコマンドで `--sku Standard_RAGRS`。

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

### 実施済み（2026-07-26）

- [x] **ストレージアカウントとコンテナ `photos` を作成**（公開アクセス無効）
- [x] **App Service（Linux / F1）を作成し、APIをデプロイ** — `az webapp deploy --type zip`
      HTTPS のみ / 最小TLS 1.2 / FTPS 無効 / HTTP/2 有効
- [x] **システム割り当てマネージドIDを有効化**（`b92eba42-f068-49ba-81b7-b15d33186fed`）
- [x] **API層の送信元IPをSQLファイアウォールに追加**（`appsvc-01`〜`appsvc-20`）
      → `possibleOutboundIpAddresses` を全部入れている。**プランを変えると増減するので都度見直す**
- [x] 接続文字列を App Service のアプリケーション設定に格納
      （`ConnectionStrings__RailAngyer` / `ConnectionStrings__Storage`）
- [x] **疎通確認** — `https://railangyer.azurewebsites.net/health/db` が
      `{"status":"ok","stations":16}` を返す（App Service → Azure SQL が通った）

```bash
# デプロイ手順（作業ディレクトリはリポジトリ直下）
dotnet publish RailAngyerApi -c Release -o /tmp/publish
(cd /tmp/publish && zip -qr ../app.zip .)
az webapp deploy -g RailAngyer -n railangyer --src-path /tmp/app.zip --type zip
```

> ⚠️ **アプリケーション設定を変えたら `az webapp restart` を打つ。**
> 設定の反映で自動再起動しないことがあり、設定したのに読めていない状態になる
> （`No database provider has been configured` はこれで起きた）。

### 次の作業

- [ ] **マネージドIDに切り替える**（`09_アプリ用ユーザー.sql` §3.2）
      IDは有効化済みなので、あとはSQL側に包含ユーザーを作り、
      接続文字列を `Authentication=Active Directory Default` に変えるだけ。
      切り替えたらパスワード方式の `railangyer_app` を削除する
- [ ] **Blob もマネージドIDに寄せる**（アカウントキーを持たずに済む）。以下を実行して
      接続文字列の代わりにユーザー委任SASを発行する形にする。
      **※ このコマンドは権限の都合で未実行**

```bash
az role assignment create \
  --assignee b92eba42-f068-49ba-81b7-b15d33186fed \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/22967d92-5dd8-41b2-903c-358fee055a5c/resourceGroups/RailAngyer/providers/Microsoft.Storage/storageAccounts/railangyer"
```

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

### 「もっと早くDBに繋がるようにできないか」への答え（2026-08-02 実測）

**無料のままで「いつでも即座」にはできない。** 実際の設定はこう。

| 項目 | 値 | 確認方法 |
|---|---|---|
| SKU | `GP_S_Gen5` / 最小 0.5 vCore | `az sql db show` |
| 自動一時停止 | **60分**（無料オファーの下限） | `autoPauseDelay: 60` |
| 無料枠 | 月 10万 vCore秒 | `useFreeLimit: true` |
| 枠を使い切ったら | **その月の残りは強制停止** | `freeLimitExhaustionBehavior: AutoPause` |
| App Service | F1・**Always On なし**（約20分で寝る） | `alwaysOn: false` |

- **温まっていれば速い。** `/health` `/health/db` とも **0.22〜0.37秒**（3回ずつ実測）。
  遅いのは寝ているときだけ
- **常時起動にはできない。** 最小0.5 vCoreで常時起動すると月およそ131万 vCore秒が要り、
  無料枠の**13倍**。無料枠で起きていられるのは月**約55時間（1日1.8時間）**。
  しかも枯渇時は強制停止なので、常時起動にすると
  「月初の2日で使い切り、残りは月末まで繋がらない」という**いまより悪い状態**になる
- **遅延源は2つある。** DBだけ直しても、App Service F1 のコールドスタートが残る

**取るべき手（すべて無料）**

1. **予定の日時を使って先に起こす。** 集合の数分前に `/health/db` を叩けば当日は温まっている。
   集合日時を持つ「予定」機能があるので、この設計といちばん噛み合う
2. **遊ぶ日だけ `autoPauseDelay` を延ばす**（60分 → 4〜6時間）。歩行セッション中に寝なくなる。
   月55時間の枠内なら5〜6回の外出ぶんは賄える
3. 起動時に起こし、UIは止めない（ビルド5で実施済み）。
   **ローカルが正**なので、寝ていても最後まで遊べる

**乗り換えは勧めない。** 無料で常時温かいものはある
（Cosmos DB無料枠は一時停止なし／Neonは再開1秒未満／Supabaseは7日無操作まで起きたまま）が、
いずれも Azure SQL + EF Core からの移行で、**スキーマの正である `06_schema.sql` を書き直す**ことになる。
上の1・2で消せる程度の遅延に対しては割に合わない。

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
