# RailAngyer TestFlight 配布準備

> 更新日: 2026-07-28。TestFlight v1.0 の正とする。

## 1. 配布ビルド

| 項目 | 値 |
|---|---|
| App名 | レイルアンギャー |
| Bundle ID | `com.non-migi.RailAngyerApp` |
| Team ID | `949FXAWTYZ` |
| バージョン | `1.0.0` |
| ビルド | `1` |
| 対象 | iPhone / iOS 17.0 以降 |
| カテゴリ | Games |
| SKU案 | `railangyer-ios` |
| 主言語 | 日本語 |

バージョンとビルドは `RailAngyerApp/project.yml` の
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を正とする。
同じバージョンを再アップロードするときは、必ずビルド番号だけを増やす。

## 2. 完了済み

- [x] 既存ロゴから、文字なし・不透明RGB・1024×1024のApp Iconを作成
- [x] ネイティブ起動画面と、アプリ内の短い読み込み画面をブランド画像で統一
- [x] 盤面の操作を整理し、ルーム名が読めるレイアウトへ調整
- [x] 設定画面にバージョン／ビルド番号を表示
- [x] `1.0.0 (1)`、Appカテゴリ、暗号輸出申告、用途説明文を設定
- [x] `PrivacyInfo.xcprivacy` を同梱
- [x] App Store Connectへ送信するTestFlight文面を
      `RailAngyerApp/TestFlight/ja-JP/` に用意
- [x] 自動署名で端末向けアーカイブを作成
- [x] Releaseビルド、アーカイブ内のInfo.plist・アイコン・プライバシー文書を確認
- [x] コア47件、アプリ80件、UI 5件、API 54件を通過

最終アーカイブは
`/tmp/RailAngyerApp-1.0.0-1-final.xcarchive`。
2026-07-28のアップロード試行では、認証とApp一覧の取得までは成功し、
Bundle IDに対応するAppレコードが未作成のため
`missingApp(bundleId: "com.non-migi.RailAngyerApp")` で停止した。
レコード作成後は同じアーカイブとExportOptionsで再送信できる。

## 3. App Store Connectへ入力する文面

そのまま貼れる本文は次に置く。

- Beta App Description:
  `RailAngyerApp/TestFlight/ja-JP/BetaDescription.txt`
- What to Test:
  `RailAngyerApp/TestFlight/ja-JP/WhatToTest.txt`
- Beta Review Notes:
  `RailAngyerApp/TestFlight/ja-JP/ReviewNotes.txt`
- Feedback Email:
  `RailAngyerApp/TestFlight/ja-JP/FeedbackEmail.txt`

TestFlight App Reviewでは「ログイン不要」を選ぶ。ローカルモードだけで主要機能を試せ、
駅へ移動しなくても画面下の手動到着ボタンで進められる。

## 4. プライバシー申告

App Store Connectの「Appのプライバシー」では、次を
「ユーザーに関連付ける」「トラッキングには使わない」「Appの機能」に設定する。

| データ | 実際の用途 |
|---|---|
| 名前 | ルーム内の表示名 |
| ユーザーID | メンバー識別子 |
| 位置情報 | 到着した駅と時刻の共有。生のGPS座標は端末外へ送らない |
| 写真またはビデオ | 駅で撮った写真のルーム内共有 |
| ゲームプレイコンテンツ | ルーム、ターン、訪問、お題、予定、出欠 |

広告、第三者トラッキング、連絡先、決済、健康データは使わない。
プライバシーポリシー本文は `16_プライバシーポリシー.md`、
公開用HTMLは `privacy-policy.html` にある。

## 5. アーカイブとアップロード

```bash
xcodegen generate --spec RailAngyerApp/project.yml

xcodebuild \
  -project RailAngyerApp/RailAngyerApp.xcodeproj \
  -scheme RailAngyerApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /tmp/RailAngyerApp-1.0.0-1.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath /tmp/RailAngyerApp-1.0.0-1.xcarchive \
  -exportOptionsPlist RailAngyerApp/ExportOptions-TestFlight.plist \
  -exportPath /tmp/RailAngyerApp-TestFlight \
  -allowProvisioningUpdates
```

`ExportOptions-TestFlight.plist` は `destination=upload` なので、最後のコマンドは
App Store Connectへの送信まで行う。送信前にApp Store Connectで同じBundle IDの
Appレコードを作っておく。

## 6. Appleアカウント側で必要な項目

- [ ] App Store ConnectでAppレコードを作成
      （名前、主言語、Bundle ID、SKU）
- [ ] Beta Review連絡先の電話番号を入力
- [ ] 必要なら公開用プライバシーポリシーURLを用意
- [ ] ビルドの処理完了後、輸出コンプライアンスが「不要」になっていることを確認
- [ ] 内部テスターグループを作成してビルドを追加
- [ ] 身内がApp Store Connectユーザーでなければ、外部テスターグループを作り
      最初のビルドをTestFlight App Reviewへ送る

外部テスター向けの最初のビルドはBeta Reviewが必要。ビルドの利用期限は90日。

## 7. 配布後の実機確認

- [ ] 2台で新規ルーム作成→招待コード参加
- [ ] お題・予定・出欠・進行・写真の双方向同期
- [ ] When In Use→Alwaysの位置情報許可導線
- [ ] 画面消灯中の到着通知
- [ ] 圏外→復帰時の送信キュー
- [ ] 地下駅の手動到着
- [ ] 4〜5時間利用時の電池残量
- [ ] 全駅の座標補正
