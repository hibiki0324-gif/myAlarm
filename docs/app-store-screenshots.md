# App Store 用スクリーンショット

## 撮影とマーケ用画像の作成

```sh
brew install fastlane   # 初回のみ
fastlane ios screenshots
```

iPhone 17 Pro Max のシミュレータ（6.9 インチ、1320×2868）で 5 枚撮り、背景とキャッチコピーを付けます。iPhone 専用アプリなので iPad 用の画像は作りません。

| 出力先 | 内容 |
| --- | --- |
| `fastlane/screenshots_raw/ja-JP/` | 撮影したままの画像（Git に入れない） |
| `fastlane/screenshots/ja/` | App Store に載せるマーケ用画像（透過なし PNG） |

| ファイル | 変更する場所 |
| --- | --- |
| キャッチコピー・背景色 | `fastlane/frame_screenshots.swift` の `slides` |
| 撮る画面と手順 | `myAlarmUITests/ScreenshotTests.swift` |
| 画面に出すデータ | `myAlarm/DemoMode.swift` |

コピーや背景色だけを直すときは、`fastlane ios frame_images` で撮影せずに作り直せます。

起動引数 `-demoMode` を付けると、デモ用のデータをメモリ上だけに読み込みます。実データには触れず、AlarmKit にも登録しません。Debug ビルド限定で、Release ビルドでは無効です。日付は「来月 8 日の 9:41」に固定されます。

## App Store Connect へのアップロード

### 事前に必要なもの

1. **Apple Developer Program への有料登録。** 無料の Personal Team では App Store Connect を使えません。
2. **App Store Connect でのアプリ登録。** バンドル ID は `com.imamurahibiki.myAlarm`、主言語は日本語です。編集できるバージョンが必要です。
3. **API キー。** App Store Connect の「ユーザとアクセス」→「統合」→「App Store Connect API」で作ります。役割は App Manager です。`.p8` ファイルは 1 回しかダウンロードできません。

### 設定

```sh
cp fastlane/.env.example fastlane/.env
```

`fastlane/.env` に次の値を入れます。`.env` と `.p8` は Git に入りません。`.p8` はリポジトリの外に置いてください。

| 変数 | 値 |
| --- | --- |
| `ASC_KEY_ID` | キー ID |
| `ASC_ISSUER_ID` | 発行者 ID |
| `ASC_KEY_PATH` | `.p8` ファイルの絶対パス |

### アップロード

```sh
fastlane ios upload_screenshots
```

アップロードするのは `fastlane/screenshots/` の画像だけです。同じ言語の既存のスクリーンショットは置き換えられます。アプリ本体とメタデータは送らず、審査にも提出しません。
