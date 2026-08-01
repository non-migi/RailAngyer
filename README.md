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
| [files/12_migration_v3_token.sql](files/12_migration_v3_token.sql) | メンバートークン用のスキーマ移行（適用済み） |
| [files/13_courses.sql](files/13_courses.sql) | 東西線・東豊線・山手線の投入（適用済み） |
| [files/18_courses_v2.sql](files/18_courses_v2.sql) | 札幌市電の投入と山手線の座標更新（適用済み） |
| [files/14_引き継ぎ.md](files/14_引き継ぎ.md) | **引き継ぎ資料**。環境・コマンド・落とし穴・途中の作業 |
| [tools/asc-crashes.py](tools/asc-crashes.py) | TestFlightのクラッシュ報告を取り出す（鍵の作り方は `15_TestFlight準備.md` §8） |
| [files/15_TestFlight準備.md](files/15_TestFlight準備.md) | v1.0の署名・メタデータ・プライバシー・配布手順 |
| [files/16_プライバシーポリシー.md](files/16_プライバシーポリシー.md) | TestFlight／App Store向けのプライバシーポリシー |
| [files/17_migration_v4_schedule_rules.sql](files/17_migration_v4_schedule_rules.sql) | 予定ルールと札幌駅座標のDB移行（適用済み） |
| [RailAngyerCore/](RailAngyerCore/) | ルール計算と駅マスタ（GPS・DB非依存。`swift test` で検証） |
| [RailAngyerApp/](RailAngyerApp/) | iOSアプリ（XcodeGen。`xcodegen generate --spec RailAngyerApp/project.yml`） |
| [RailAngyerApi/](RailAngyerApi/) | ASP.NET Core の API（フェーズ2。`dotnet test` で検証） |
| [tools/](tools/) | シミュレータ用のGPXルート（南北線の歩行を再現） |

`.html` はブラウザで開いてください。

## 現在地

フェーズ1〜4の「作るもの」は一通り実装済み。
**残りは実機での2台通し確認と、座標・テンポ・電池を確かめる実地テスト。**

- Azure SQL Database 作成済み（無料オファー / Japan East / サーバーレス）
- スキーマ適用済み（10テーブル、南北線16駅を投入）
- アプリ用の最小権限ユーザー作成済み
- iOSアプリ：フェーズ1の実装は完了。**実地テスト待ち**
- API：参加・ミッション・進行・写真・予定まで実装（54テスト）
- **App Service（Linux / F1 無料 / Japan West）にデプロイ済み** —
  `https://railangyer.azurewebsites.net/health/db` が DB まで疎通
- 写真：ストレージ・コンテナ `photos` 作成済み。**SAS発行 → Blobへ直接アップロード →
  メタ登録 → 表示 → 削除を実物で確認済み**
- アプリ：ホームから明示的に開始し、参加/ルーム・お題・予定・進行を扱う構成
- 記録：複数の旅、実写真の地図ピン、時間、分/km、連続ペース色まで実装
- 予定：ルールセットを先に決め、日本時間・日本のカレンダーで作成
- 駅座標：札幌3路線を国土数値情報 N02-22（JGD2011）へ補正済み
- コースは5本（南北線・東西線・東豊線・山手線・札幌市電）。設定から切り替えられる。
  **山手線と市電は一周でき、内回り／外回りを選べる**
- TestFlight v1.0.0 (1)：App Icon、起動画面、プライバシーマニフェスト、
  配布文面、Explicit App IDを用意し、ビルド1をApp Store Connectへアップロード済み。
  緑アイコンと新UIのビルド2もApp Store Connectへアップロード済み（処理中）
  （`15_TestFlight準備.md`）
- **フェーズ2〜4の作るものは揃った。**残るは実機での通し確認と実地テスト

## テスト

```bash
swift test --package-path RailAngyerCore     # ルール計算・駅マスタ・ペース 47件
xcodebuild -project RailAngyerApp/RailAngyerApp.xcodeproj -scheme RailAngyerApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test   # 81件 + UI 6件
dotnet test RailAngyerApi.Tests               # API 54件
```
