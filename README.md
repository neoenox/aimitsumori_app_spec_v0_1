# 外構見積もり比較

**外構工事**の複数社見積書を、単純な総合点や順位ではなく、**価格・工事範囲・別途費用・オプション・要望との差・不明点**として整理するFlutterアプリです。

PDF・写真・連続撮影から外構工事の見積書を取り込み、端末内OCRの結果を確認・修正したうえで、土間コンクリート、カーポート、フェンス、造成・掘削、残土処分、重機回送などを含む固定18カテゴリで比較し、業者への確認質問、見積改訂履歴を作成します。

> **対応範囲:** 現行版は外構工事専用です。住宅内装リフォーム、引越し、車検など、固定18カテゴリに含まれない分野の見積書は比較対象にしないでください。OCRで文字を読めても、その分野向けの比較結果としての妥当性は保証しません。

> Flutter実装は `main` ブランチです。リポジトリの既定ブランチが切り替わるまでは、clone時に `-b main` を指定してください。

## 主な機能

- 案件の作成、検索、削除
- 18カテゴリの要望チェックリスト
- PDF・写真・複数ページ撮影からの見積取込
- 日本語OCR結果、金額、数量、単位、仕様の確認・修正
- OCR信頼度、合計不一致、数量×単価不一致のレビュー
- 複数社のカテゴリ別比較
- 要望との差異と確認質問の生成
- 同一業者の見積改訂履歴と版間差分
- 改訂版を選択した読み取り専用比較
- PDF・PNG・CSV・テキスト共有
- AdMobバナー・リワード広告
- 広告削除の非消費型購入・復元
- ダークモード
- 端末内データの一括削除

## 技術構成

- Flutter / Dart
- SQLite (`sqflite`)
- Google ML Kit Text Recognition
- Camera
- Google Mobile Ads
- Google Play / App Store In-App Purchase

案件、見積、要望、比較結果、改訂履歴はSQLiteへ保存します。OCR処理は端末上で実行し、見積内容をアプリ独自のサーバーへ送信しません。

購入検証時のみ、ストアの検証データを設定済みの `PURCHASE_VERIFICATION_URL` へ送信します。

## セットアップ

```bash
git clone -b main https://github.com/kaenozu/aimitsumori_app_spec_v0_1.git
cd aimitsumori_app_spec_v0_1
flutter pub get
flutter run
```

開発ビルドではGoogle公式のテスト広告IDを使用します。

## 開発用コマンド

```bash
# フォーマット
dart format lib test integration_test

# 静的解析
flutter analyze --no-fatal-infos

# Unit / Widget test
flutter test

# AndroidエミュレータE2E
flutter test -d emulator-5554 test/integration/sprint5_e2e_test.dart -r expanded

# Debug APK
flutter build apk --debug
```

Makefileを使用する場合:

```bash
make run
make analyze
make test
make build-apk
```

## Android Release

### 1. リリース署名を設定

`android/key.properties.example` を `android/key.properties` へコピーし、本番用keystoreを指定します。

```properties
storePassword=CHANGE_ME
keyPassword=CHANGE_ME
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

`android/key.properties` とkeystoreはGit管理対象外です。

### 2. 本番環境変数を設定

```powershell
$env:ADMOB_APP_ID='ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY'
$env:ADMOB_ANDROID_BANNER_ID='ca-app-pub-XXXXXXXXXXXXXXXX/BBBBBBBBBB'
$env:ADMOB_ANDROID_REWARDED_ID='ca-app-pub-XXXXXXXXXXXXXXXX/RRRRRRRRRR'
$env:REMOVE_ADS_PRODUCT_ID='remove_ads_pro'
$env:PURCHASE_VERIFICATION_URL='https://example.com/api/store/verify'
```

Releaseビルドでは次を検証します。

- 本番署名鍵が存在する
- debug keystore / `androiddebugkey` を使っていない
- AdMob IDが正しい形式で、GoogleのテストIDではない
- 課金商品IDが正しい形式である
- 購入検証URLがHTTPSである

### 3. AABまたはAPKを作成

```powershell
.\tool\build_android_release.ps1 -Artifact appbundle
.\tool\build_android_release.ps1 -Artifact apk
```

生成物:

```text
build/app/outputs/bundle/release/app-release.aab
build/app/outputs/flutter-apk/app-release.apk
```

Release APKのパッケージ、AdMob Application ID、署名を監査する場合:

```powershell
.\tool\audit_android_release.ps1 -ExpectedAdMobAppId $env:ADMOB_APP_ID
```

## iOS Release

```bash
cp ios/Flutter/ReleaseSecrets.xcconfig.example \
  ios/Flutter/ReleaseSecrets.xcconfig
```

`ReleaseSecrets.xcconfig` に本番AdMob Application IDを設定し、Dart defineを渡します。

```bash
flutter build ios --release \
  --dart-define=ADMOB_IOS_BANNER_ID='ca-app-pub-.../...' \
  --dart-define=ADMOB_IOS_REWARDED_ID='ca-app-pub-.../...' \
  --dart-define=REMOVE_ADS_PRODUCT_ID='remove_ads_pro' \
  --dart-define=PURCHASE_VERIFICATION_URL='https://example.com/api/store/verify'
```

署名とProvisioning ProfileはXcode側で設定してください。

## 購入検証API

アプリは購入・復元イベントを受けると、HTTPS POSTで次の情報を送信します。

```json
{
  "productId": "remove_ads_pro",
  "purchaseId": "...",
  "transactionDate": "...",
  "source": "google_play_or_app_store",
  "serverVerificationData": "...",
  "localVerificationData": "..."
}
```

成功応答:

```json
{
  "valid": true,
  "productId": "remove_ads_pro"
}
```

サーバー側ではGoogle Play Developer APIまたはApp Store Server APIを使用し、購入の真正性、商品ID、返金・失効状態を検証してください。

通信障害、HTTP 429、サーバー5xxは再試行可能エラーとして扱い、直近に検証済みの広告削除権利を即座には剥奪しません。

## データとプライバシー

- 案件・見積・比較・改訂履歴は端末内SQLiteへ保存します。
- OCRは端末上で実行します。
- 連続撮影した元画像はOCR確認中だけ一時保存し、画面終了時に削除します。
- Android Auto Backupは無効です。
- PDF・画像・CSV・テキストは、ユーザーが共有操作を実行した場合だけ共有先へ渡します。
- 購入検証データは設定済みの購入検証APIへ送信します。
- 「全データを削除」で案件、見積、比較結果、改訂履歴、要望、OCR確認状態、残存スキャン画像を削除します。

詳細は [PRIVACY.md](PRIVACY.md) を参照してください。

## CI

GitHub Actionsは次を検証します。

- 依存解決
- Dart format
- Flutter analyze
- Unit / Widget test
- Debug APK build
- AndroidエミュレータE2E
- 一時署名鍵を使用したRelease APK compile

CI用の署名鍵、広告ID、商品ID、購入検証URLは検証専用であり、ストア提出には使用しません。

## 主なディレクトリ

```text
lib/
  data/          マスタ・サンプルデータ
  repositories/ 永続化境界
  screens/       画面
  services/      DB、OCR、比較、改訂、広告・課金
  widgets/       共通Widget

test/            Unit / Widget / SQLite integration test
integration_test/ アプリE2E
tool/            Release build / audit scripts
```

公開前の確認項目は [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) を参照してください。
