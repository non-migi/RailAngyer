# RailAngyer TestFlight 配布準備

> 更新日: 2026-08-01。TestFlight v1.0 の正とする。

## 1. 配布ビルド

| 項目 | 値 |
|---|---|
| App Store Connect名 | RailAngyer - レイルアンギャー |
| Apple ID | `6795570321` |
| Bundle ID | `com.non-migi.RailAngyerApp` |
| Team ID | `949FXAWTYZ` |
| バージョン | `1.0.0` |
| ビルド | `4` |
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
- [x] 緑のApp Icon、歩行マスコットの起動／DB読み込み画面へ刷新
- [x] ホームと明示的な「旅をスタート」、複数の旅の記録を追加
- [x] 予定のルールセット、日本基準カレンダー、お題の効果／初期値廃止を反映
- [x] 札幌3路線の駅座標を国土数値情報 N02-22（JGD2011）へ更新
- [x] 写真そのものを使う地図ピンと、連続的なペース配色を追加
- [x] ビルド2候補でコア47件、アプリ81件、UI 6件、API 54件を通過
- [x] ビルド3で、予定の即時反映・予定段階のお題・暗所の視認性・リセットの堅牢化に対処。
      コア47件、アプリ91件、UI 8件、API 54件を通過
      （`ArrivalUITests` の1件はビルド2の時点から失敗しており、位置シミュレーションの既存問題）
- [x] `17_migration_v4_schedule_rules.sql` を本番DBへ適用し、対応APIをApp Serviceへ再配置

Explicit App ID登録後の最終アーカイブは
`/tmp/RailAngyerApp-1.0.0-1-explicit.xcarchive`。
2026-07-28 23:39 JSTにApp Store Connectへのアップロードが成功し、
ビルド `1.0.0 (1)` の処理が開始された。

今回の変更版 `1.0.0 (2)` は、2026-08-01 09:11 JSTにアップロード成功。

不具合報告（予定の即時反映・予定段階のお題・暗所の視認性・リセットのクラッシュ）に
対処した `1.0.0 (3)` を、2026-08-01 18:29 JSTにアップロード成功。App Store Connectで処理中。
アーカイブは `/tmp/RailAngyerApp-1.0.0-3.xcarchive`。

> ⚠️ **クラッシュログはこの環境からは見えない。**
> 端末が繋がっておらず（`~/Library/Logs/CrashReporter/MobileDevice/` が無い）、
> App Store Connect API の鍵も置いていないため。取得の手順は §8。

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
  -archivePath /tmp/RailAngyerApp-1.0.0-2.xcarchive \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath /tmp/RailAngyerApp-1.0.0-2.xcarchive \
  -exportOptionsPlist RailAngyerApp/ExportOptions-TestFlight.plist \
  -exportPath /tmp/RailAngyerApp-TestFlight \
  -allowProvisioningUpdates
```

`ExportOptions-TestFlight.plist` は `destination=upload` なので、最後のコマンドは
App Store Connectへの送信まで行う。送信前にApp Store Connectで同じBundle IDの
Appレコードを作っておく。

## 6. Appleアカウント側で必要な項目

- [x] Explicit App IDとApp Store ConnectのAppレコードを作成
      （名前、主言語、Bundle ID、SKU）
- [x] ビルド `1.0.0 (1)` をApp Store Connectへアップロード
- [x] ビルド `1.0.0 (2)` をApp Store Connectへアップロード
- [x] ビルド `1.0.0 (3)` をApp Store Connectへアップロード（不具合報告への対処版）
- [x] App Store Connect API のキーを設定し、ビルドとクラッシュ報告を自動で見られるようにした
- [x] ビルド `3` のテスト項目（日本語）をAPIから登録
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
- [x] 札幌3路線の全駅座標補正（国土数値情報 N02-22）

---

## 8. クラッシュ報告を見る

落ちた原因を追うには、**端末の解析データ**か **App Store Connect API** のどちらかが要る。
急ぐときは前者、これから何度も見るなら後者。

### 8.1 端末から1件だけ渡す（すぐできる）

1. iPhone の **設定 ＞ プライバシーとセキュリティ ＞ 解析と改善**
2. **「iPhone解析を共有」をオン**にする（オフだとログ自体が残らない）
3. **解析データ** を開き、`RailAngyerApp-2026-…-.ips` を選ぶ
4. 右上の共有から、AirDrop などで Mac に渡す

> ⚠️ **共有がオフだった場合、過去のクラッシュのログは残っていない。**
> オンにしてから、もう一度落ちる操作を再現してもらう必要がある。

### 8.2 App Store Connect API の鍵を作る（以後は自動で取れる）

**鍵は作成時に一度しかダウンロードできない。** 無くしたら作り直しになる。

1. https://appstoreconnect.apple.com にサインインする
2. 上部の **ユーザーとアクセス** を開く
3. **各種統合**（Integrations）タブ → 左の **App Store Connect API** → **チームキー**
4. 初回のみ「名前と組織の情報」を求められるので、指示に従って有効化する
5. **アクセスを許可されたキー** の **＋** を押す
6. 名前は用途が分かるもの（例: `RailAngyer crash reader`）
7. **アクセス（役割）** は **App Manager** を選ぶ
   （TestFlight のフィードバックを読むのに足りる。Admin は不要）
8. **生成** を押し、**「APIキーをダウンロード」** から `AuthKey_XXXXXXXXXX.p8` を保存する
9. 同じ画面で次の2つを控える
   - **キーID**（`AuthKey_` の後ろと同じ10桁）
   - **Issuer ID**（ページ上部にある UUID。キーごとではなくチームで1つ）

### 8.3 Mac に置く

> 2026-08-01 時点: **設定は完了している。** 鍵 `AuthKey_BMCT4QBV35.p8` と
> `asc-config.json`（Issuer ID）を `~/private_keys/`（600）に配置し、疎通を確認した。
> この鍵は**チームキー**（`sub: user` の個人用キー方式では 401 になった）。
> 別のMacで設定し直すときは `./tools/asc-setup.sh <Issuer ID の UUID>` を実行する。


```bash
mkdir -p ~/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/private_keys/
chmod 600 ~/private_keys/AuthKey_XXXXXXXXXX.p8

# Issuer ID を一緒に控えておく（キーIDはファイル名から読む）
cat > ~/private_keys/asc-config.json <<'JSON'
{ "issuerId": "ここに Issuer ID の UUID" }
JSON
chmod 600 ~/private_keys/asc-config.json
```

> ⚠️ **`.p8` はリポジトリに入れない。** ホーム配下に置き、パーミッションは 600 にする。
> この鍵はアップロードやビルド操作もできるので、漏れると配布に手を出される。

### 8.4 取り出す

> ⚠️ **エンドポイントの形に注意。** `/v1/betaFeedbackCrashSubmissions` を単体で叩くと
> `403 The resource does not allow GET_COLLECTION` になる。
> **App からの関連**（`/v1/apps/{id}/betaFeedbackCrashSubmissions`）として取りにいく。


```bash
python3 tools/asc-crashes.py                  # 直近のクラッシュ報告を一覧
python3 tools/asc-crashes.py --save /tmp/crash # 本体(.ips)も保存する
```

追加のインストールは要らない（JWT の署名は `openssl` に任せている）。

### 8.5 うまくいかないとき

| 症状 | 見るところ |
|---|---|
| `鍵が見つかりません` | `~/private_keys/AuthKey_*.p8` があるか。ファイル名を変えていないか |
| `Issuer ID が分かりません` | `~/private_keys/asc-config.json` の `issuerId` |
| `APIが 401 を返しました` | 鍵IDとIssuer IDの取り違え。`.p8` の中身が壊れていないか |
| `APIが 403 を返しました` | キーの役割が足りない。App Manager 以上にする |
| `Appが見つかりません` | キーの「アクセスするApp」に RailAngyer が含まれているか |
| `クラッシュ報告はまだ届いていません` | テスターの端末で解析共有がオフ。§8.1 の2を確認してもらう |

> 同じ鍵はアップロードにも使える。
> `xcrun altool --upload-app -f app.ipa -t ios --apiKey <キーID> --apiIssuer <Issuer ID>`

---

## 9. 現在の配布状況（2026-08-01 API で確認）

| ビルド | 処理 | 内部テスト | 外部テスト | 期限 |
|---|---|---|---|---|
| `1.0.0 (4)` | VALID | **配布中**（IN_BETA_TESTING） | 未提出 | 2026-10-30 |
| `1.0.0 (3)` | VALID | 配布中 | 未提出（READY_FOR_BETA_SUBMISSION） | 2026-10-30 |
| `1.0.0 (2)` | VALID | 配布中 | 未提出 | 2026-10-29 |
| `1.0.0 (1)` | VALID | 配布中 | 未提出 | 2026-10-26 |

- テスターグループ: `テスト`（内部・全ビルド自動配布）／`外部テスト`（外部・公開リンク無効）
- ビルド3のテスト項目（日本語）は登録済み。自動通知も有効
- ビルド4のテスト項目（日本語）も登録済み（自動で作られた `ja` があったので PATCH で更新した）
- **クラッシュ報告は1件取得できた**（2026-08-01 19:01 JST / iPhone 11 / iOS 26.6 / ビルド2）。
  原因は「消したお題を掴んだままのターン」で、ビルド4で修正済み

> **外部テスターへ配るには Beta App Review への提出が要る**（内部テスターは提出不要）。
> 身内が App Store Connect のユーザーでないなら、`外部テスト` グループにビルド3を追加して提出する。

### 取得できたクラッシュ（2026-08-01）

```
Exception Type: EXC_BREAKPOINT (SIGTRAP)
0  libswiftCore   _assertionFailure
1  SwiftData      _InvalidFutureBackingData.getValue(forKey:)
4  RailAngyerApp  Mission.id.getter
5  RailAngyerApp  closure #1 in GameSessionStore.missionCandidates(at:)  ← ここ
8  RailAngyerApp  closure #1 in TurnFlowView.landed(_:)
```

**消したお題を `Turn.selectedMission` が掴んだまま**で、その `id` を読んで落ちていた。
着地したターンを開くたびに落ちるので、その状態で終了すると**起動直後に落ち続ける**。
ビルド4で、①消す前に参照を外す ②読むときは `persistentModelID` で突き合わせる
③起動時に古い参照を掃除する、の3つを入れた。

> **クラッシュ報告が集まる条件**は、テスターが「フィードバックを送信」から送るか、
> 端末で「iPhone解析を共有」がオンで TestFlight 経由のビルドが落ちるか、のどちらか。
> どちらも満たさないと、落ちても記録は残らない。
