<img src="assets/logo.png" alt="RailAngyer — レイルアンギャー" width="520">

# RailAngyer — レイルアンギャー

サイコロで駅を巡る徒歩すごろくアプリ（身内向け / iOS・SwiftUI）。

「鉄道（Rail）」×「行脚（あんぎゃ）」。
実際に鉄道の駅を歩いて巡り、サイコロの出目だけ駅を進み、着地した駅でチームのミッションを行う。
第1弾は札幌市営地下鉄 南北線（麻生〜真駒内、16駅）。

## ドキュメント

| ファイル | 内容 |
|---|---|
| [files/01_企画仕様書.md](files/01_企画仕様書.md) | コンセプト・コアループ・可変ルール・決定事項 |
| [files/02_データ設計.md](files/02_データ設計.md) | 初期のデータ設計（ver.1。考え方の記録） |
| [files/03_Azure構成と料金.md](files/03_Azure構成と料金.md) | Azure の構成・無料枠・実際に作成したリソース |
| [files/04_ロードマップ.md](files/04_ロードマップ.md) | 開発フェーズと将来展開 |
| [files/05_フロー仕様.html](files/05_フロー仕様.html) | 状態遷移・ターンの手順・判定ルール・例外処理 |
| [files/06_schema.sql](files/06_schema.sql) | Azure SQL の DDL・南北線16駅の投入・主要クエリ |
| [files/07_データモデル仕様.html](files/07_データモデル仕様.html) | 全10テーブルの列定義・制約・導出値・設計判断 |
| [files/08_画面仕様.html](files/08_画面仕様.html) | 全21画面の表示項目・操作・遷移・実装範囲 |
| [files/09_アプリ用ユーザー.sql](files/09_アプリ用ユーザー.sql) | アプリ／API用の最小権限ユーザーとロール |
| [files/10_アプリ設計.md](files/10_アプリ設計.md) | SwiftDataモデル・状態管理・位置判定・GPXテスト手順 |
| [files/11_API設計.md](files/11_API設計.md) | フェーズ2のAPI。認証・エンドポイント・冪等性・Blob |
| [files/12_migration_v3_token.sql](files/12_migration_v3_token.sql) | メンバートークン用のスキーマ移行（**未適用**） |
| [RailAngyerCore/](RailAngyerCore/) | ルール計算と駅マスタ（GPS・DB非依存。`swift test` で検証） |
| [RailAngyerApp/](RailAngyerApp/) | iOSアプリ（XcodeGen。`xcodegen generate --spec RailAngyerApp/project.yml`） |
| [RailAngyerApi/](RailAngyerApi/) | ASP.NET Core の API（フェーズ2。`dotnet test` で検証） |
| [tools/](tools/) | シミュレータ用のGPXルート（南北線の歩行を再現） |

`.html` はブラウザで開いてください。

## 現在地

フェーズ0（意思決定）完了、フェーズ1（ローカルMVP）に着手するところ。

- Azure SQL Database 作成済み（無料オファー / Japan East / サーバーレス）
- スキーマ適用済み（10テーブル、南北線16駅を投入）
- アプリ用の最小権限ユーザー作成済み
- iOSアプリ：フェーズ1の実装は完了。**実地テスト待ち**
- API：参加・ミッション・進行まで実装（34テスト）
- **App Service（Linux / F1 無料 / Japan West）にデプロイ済み** —
  `https://railangyer.azurewebsites.net/health/db` が DB まで疎通
- ストレージアカウントとコンテナ `photos` 作成済み。**写真APIはこれから**

## テスト

```bash
swift test --package-path RailAngyerCore     # ルール計算 35件
xcodebuild -project RailAngyerApp/RailAngyerApp.xcodeproj -scheme RailAngyerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test   # 27件 + UI 3件
dotnet test RailAngyerApi.Tests               # API 34件
```
