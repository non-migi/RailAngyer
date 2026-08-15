# RailAngyer TestFlight 配布準備

> 更新日: 2026-08-11。TestFlight v1.0 の正とする。

## 1. 配布ビルド

| 項目 | 値 |
|---|---|
| App Store Connect名 | RailAngyer - レイルアンギャー |
| Apple ID | `6795570321` |
| Bundle ID | `com.non-migi.RailAngyerApp` |
| Team ID | `949FXAWTYZ` |
| バージョン | `1.0.0` |
| ビルド | `27` |
| 対象 | iPhone / iOS 17.0 以降 |
| カテゴリ | Games |
| SKU案 | `railangyer-ios` |
| 主言語 | 日本語 |

バージョンとビルドは `RailAngyerApp/project.yml` の
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を正とする。
同じバージョンを再アップロードするときは、必ずビルド番号だけを増やす。

## 2. 完了済み

- [x] 既存ロゴから、文字なし・不透明RGB・1024×1024のApp Iconを作成
- [x] **アイコンの地色を落ち着かせた**（2026-08-08）。
      彩度96%・明度38%の放射状グラデーション（#046428）は濃すぎたため、
      #4CAB72 → #357F55 の穏やかな縦グラデーションに置き換え。
      起動画面の地色も同じ色に合わせ、アイコンからつながって見えるようにした。
      **元の画像は `files/assets/AppIcon-1024-original.png` に残してある**
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
- [x] 予定を全面的に作り直した（コース→区間→名前→道のり→集合日時→集合場所→詳細設定の順。
      サイコロ・お題を任意にし、終わった予定は翌日から自動で畳む）。
      設定は「言語・募金・使い方とお約束・アプリ情報」の4項目に整理し、ルール類は予定側へ移した
- [x] スタート駅も1駅目として訪問記録・写真を残せるようにした。お題の見え方の既定を
      「いつでも見える」にし、同時にサイコロを振って負けた側は自動で相手の進行に追いつくようにした
- [x] 別ライン `worktree-plan-map-share`（多言語8言語・海外コース7本・大阪環状線・
      地図の軌跡・写真ギャラリー・応援課金）を `main` へ統合（マージコミット `a793fd8`）
- [x] `19_courses_v3` / `22_courses_v4` / `23_courses_v5` / `24_courses_v6` /
      `25_migration_v5_schedule_detail` / `26_migration_v6_mission_visibility_default` を
      2026-08-11 01:20〜01:25 JSTに本番DBへ適用。コースは14本・341駅に
- [x] 統合版APIを2026-08-11 01:29 JSTにApp Serviceへ再配置し、
      `/health` `/health/db` `/courses`（14件）で疎通確認
- [x] コア94件・API64件・アプリ(ユニット)182件・UI21件が全通過

Explicit App ID登録後の最終アーカイブは
`/tmp/RailAngyerApp-1.0.0-1-explicit.xcarchive`。
2026-07-28 23:39 JSTにApp Store Connectへのアップロードが成功し、
ビルド `1.0.0 (1)` の処理が開始された。

今回の変更版 `1.0.0 (2)` は、2026-08-01 09:11 JSTにアップロード成功。

不具合報告（予定の即時反映・予定段階のお題・暗所の視認性・リセットのクラッシュ）に
対処した `1.0.0 (3)` を、2026-08-01 18:29 JSTにアップロード成功。App Store Connectで処理中。
アーカイブは `/tmp/RailAngyerApp-1.0.0-3.xcarchive`。

コースを場所からたどれるようにし、地図と歩く目安・予定の共有を入れた `1.0.0 (6)` を、
2026-08-02 00:22 JSTにアップロード成功。**同 00:30 に VALID・内部テスト配布中**。
アーカイブは `/tmp/RailAngyerApp-1.0.0-6.xcarchive`。
テスト内容（日本語）は `tools/asc-whattotest.py 6` で登録済み。

**ビルド6は配ってすぐクラッシュ報告が来た**（「阪急を選ぶとクラッシュ」/ 2026-08-02 00:33 JST）。
原因は阪急ではなく `SyncService` のスレッド（`14_引き継ぎ.md` §5）。
直した `1.0.0 (7)` を 2026-08-02 00:43 JSTにアップロード。

導線整理版（盤面のボタン集約・「ふりかえり」「過去の旅」への改名・予定→お題のpush遷移・
「みんなで遊ぶ」のホーム格上げ・一周モードで保存できない不具合の修正）を
`1.0.0 (26)` として2026-08-10 20:08 JSTにアップロード成功。
アーカイブは `/tmp/RailAngyerApp-1.0.0-26.xcarchive`。

**予定の作り直し・設定の4項目化・多言語・海外コース7本・地図の軌跡・応援課金を合流させた統合版**
`1.0.0 (27)` を2026-08-11 01:33 JSTにアップロード成功（App Store Connectで処理中）。
アーカイブは `/tmp/RailAngyerApp-1.0.0-27.xcarchive`。
別ライン（`worktree-plan-map-share`）はこのビルドで `main` に統合済みで、以後は分けない
（統合の経緯は `14_引き継ぎ.md` §10）。テスト項目（日本語）は
`RailAngyerApp/TestFlight/ja-JP/WhatToTest.txt` を更新済み。

指摘対応版 `1.0.0 (28)`(2026-08-11)、写真共有・お題の取り組み方の版 `1.0.0 (29)`(2026-08-12)に続き、
**9言語対応版(ヒンディー語追加・全文言のアプリ内言語追随・String Catalog 64→527キー)**
`1.0.0 (30)` を2026-08-14 07:43 JSTにアップロード成功。
アーカイブは `/tmp/RailAngyerApp-1.0.0-30.xcarchive`。

> ⚠️ **ビルド番号はApp Store Connect側が正。** この文書の通し番号（1〜7）と違い、
> 実際のアップロード済み番号は25まで進んでいた（低い番号は
> 「bundle version must be higher than ‘25’」で弾かれる）。
> `CURRENT_PROJECT_VERSION` はApp Store Connectの実番号に合わせて上げていく
> （2026-08-11の統合で27とした）。

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

広告、第三者トラッキング、連絡先、健康データは使わない。

> ⚠️ **応援課金（TipJar）を入れたので「決済は使わない」は過去の話。**
> App内課金（消耗型チップ）があるため、App Storeのプライバシー質問では
> 「購入（Purchase History）」の申告が必要になる場合がある
> （StoreKit経由でAppleが処理し、アプリ側で購入履歴を蓄積しない構成なら
> 申告不要とされる場合もある。Connectの質問文に沿って判断する）。
>
> - [ ] App Store Connect「Appのプライバシー」で購入まわりの申告を見直した
>   （申告値の記録：＿＿＿＿＿＿＿＿）

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

> ⚠️ **`error: exportArchive Failed to Use Accounts` が出たら、APIキーで送る。**
> Xcode に入れた Apple ID のセッションが切れると出る。
> サインインし直さなくても、**クラッシュ報告に使っているのと同じ鍵**で送れる
> （GUIでのサインインが不要になるので、こちらを既定にしてよい）。
>
> ```bash
> ISSUER=$(python3 -c "import json;print(json.load(open('$HOME/private_keys/asc-config.json'))['issuerId'])")
> xcodebuild -exportArchive \
>   -archivePath /tmp/RailAngyerApp-<バージョン>-<ビルド>.xcarchive \
>   -exportOptionsPlist RailAngyerApp/ExportOptions-TestFlight.plist \
>   -exportPath /tmp/RailAngyerApp-TestFlight \
>   -allowProvisioningUpdates \
>   -authenticationKeyPath "$HOME/private_keys/AuthKey_BMCT4QBV35.p8" \
>   -authenticationKeyID BMCT4QBV35 \
>   -authenticationKeyIssuerID "$ISSUER"
> ```
>
> **アーカイブ（`archive`）は鍵が無くても通る。** 詰まるのは送信の段だけ。

## 6. Appleアカウント側で必要な項目

- [x] Explicit App IDとApp Store ConnectのAppレコードを作成
      （名前、主言語、Bundle ID、SKU）
- [x] ビルド `1.0.0 (1)` をApp Store Connectへアップロード
- [x] ビルド `1.0.0 (2)` をApp Store Connectへアップロード
- [x] ビルド `1.0.0 (3)` をApp Store Connectへアップロード（不具合報告への対処版）
- [x] ビルド `1.0.0 (4)`（起動時クラッシュの修正）と `1.0.0 (5)`（起動の待ち・環状線・市電）を送信
- [x] ビルド `1.0.0 (26)`（導線整理・一周モードの保存修正）を2026-08-10に送信
- [x] ビルド `1.0.0 (27)`（予定の作り直し・設定整理・多言語・海外コース・応援課金の統合版）を
      2026-08-11 01:33 JSTに送信
- [x] App Store Connect API のキーを設定し、ビルドとクラッシュ報告を自動で見られるようにした
- [x] ビルド `1.0.0 (6)`（場所からたどるコース選択・区間の地図と歩く目安・予定の共有・阪急京都本線）を送信
- [x] ビルド `3` のテスト項目（日本語）をAPIから登録
- [x] テスト項目の登録を `tools/asc-whattotest.py` にまとめた
      （**Xcodeからの送信では文面が付かない**ので、上げるたびに打つ）
- [ ] App Store Connect の年齢レーティング設定を確認し、ここに記録する
      - 設定値: `[未記入。確認したらここに書く]`
      - 確認日: `[未記入]`
      > ⚠️ **位置情報の利用・利用者生成コンテンツ（お題・写真の共有）・アプリ内課金（応援）が
      > あるアプリ**として申告に注意する。UGCの質問（フィルタリング・通報手段の有無）は、
      > 通報窓口（利用規約 §12、メール）とルーム内削除を前提に答える
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

## 9. 現在の配布状況（2026-08-02 API で確認。ビルド27の行は未確認）

| ビルド | 処理 | 内部テスト | 外部テスト | 期限 |
|---|---|---|---|---|
| `1.0.0 (27)` | 処理中（アップロード直後。§1・§2参照） | [要確認] | [要確認] | [要確認] |
| `1.0.0 (6)` | VALID | **配布中**（IN_BETA_TESTING） | 未提出（READY_FOR_BETA_SUBMISSION） | 2026-10-30 |
| `1.0.0 (5)` | VALID | 配布中（IN_BETA_TESTING） | 未提出 | 2026-10-30 |
| `1.0.0 (4)` | VALID | 配布中 | 未提出 | 2026-10-30 |
| `1.0.0 (3)` | VALID | 配布中 | 未提出（READY_FOR_BETA_SUBMISSION） | 2026-10-30 |
| `1.0.0 (2)` | VALID | 配布中 | 未提出 | 2026-10-29 |
| `1.0.0 (1)` | VALID | 配布中 | 未提出 | 2026-10-26 |

> ビルド27の処理状況（VALID化・内部テスト配布）は、アップロードから数分〜十数分かかる。
> `python3 tools/asc-crashes.py` と同じ鍵を使えば `tools/asc-release.py` 等からAPIで確認できる。
> 確認でき次第、この表の該当行と§1・§2の記述を実測値に更新すること。

- テスターグループ: `テスト`（内部・全ビルド自動配布）／`外部テスト`（外部・公開リンク無効）
- ビルド6のテスト項目（日本語）も登録済み。
  **`/v1/builds/<id>/betaGroups` は GET を許していない**（403。作成と削除のみ）ので、
  どのグループに配られているかはAPIからは読めない。内部は自動配布の設定で全ビルドに配られる
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
