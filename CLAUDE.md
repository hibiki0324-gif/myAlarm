# CLAUDE.md

交代勤務向けの個人用 iOS アラームアプリ。概要と機能は README.md を参照。

## やりとり

- ユーザーとの会話、コードのコメント、UI の文言、コミットメッセージはすべて日本語。
- 実機は iPhone 12（iOS 26）。AlarmKit の鳴動はシミュレータでは確認しづらいので、アラームまわりの変更は実機での確認をユーザーに依頼する。
- 署名は無料アカウント（Personal Team）なので、実機に入れたアプリは 7 日で起動できなくなる。週 1 回は Xcode から入れ直す必要がある。

## ビルド

```sh
xcodebuild -project myAlarm.xcodeproj -scheme myAlarm \
  -destination 'generic/platform=iOS Simulator' -quiet build
```

テストターゲットはまだない。

## 構成と設計の前提

- SwiftUI + SwiftData + AlarmKit。外部依存なし。デプロイメントターゲットは iOS 26.0。
- ビルド設定で `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` が有効。MainActor 外で使う型には `nonisolated` が必要（例: `ShiftAlarmMetadata`）。
- データの流れ: SwiftData のモデル → `AlarmPlanner.plans(...)`（純粋関数）→ `AlarmScheduler` が AlarmKit に登録。
- **14 日先まで登録する方式**: iOS ではアプリが指定日に自分で切り替えられないため、`AlarmPlanner.horizonDays`（14 日）先までの日付指定アラームをまとめて登録しておく。同期のたびに既存のアラームをすべて取り消して登録し直す。新しい機能もこの方式を前提に考える。
- 同期のきっかけ: `ContentView.dataSignature` の変化、アプリがアクティブになったとき、バックグラウンド更新（`com.imamurahibiki.myAlarm.refresh`）。
  - **アラームに影響するプロパティをモデルに追加したら、`dataSignature` にも追加すること。** 追加しないと変更が AlarmKit に反映されない。
- SwiftData のコンテナは `AppData.container`（MyAlarmApp.swift）で共有する。アラームの「起きた」ボタン（`WakeUpIntent`）からアプリが裏で起動されたときもこれを使う。
- 「起きた」で止めた範囲は `AlarmScheduler.suppressedUntil`（UserDefaults に保存）で持つ。この時刻までのアラームは同期時に登録しない。止める範囲は `AlarmPlanner.seriesEnd`（間隔 `seriesGap` 以内で連なるアラーム）で決める。
- 優先順位: 予約（`ShiftReservation`）> 基本テンプレート（`isActive` の `AlarmTemplate`）。予約の `template == nil` は「休み」。
- `Info.plist` に `NSAlarmKitUsageDescription` とバックグラウンド更新の ID がある。ID を変えるときは `AlarmScheduler.refreshTaskID` と両方を直す。

## Git

- `project.pbxproj` の `DEVELOPMENT_TEAM` はローカルの署名設定なので、ユーザーの指示がない限りコミットに含めない。
- コードの変更は main から作業ブランチを切り、PR を作ってマージする。
