# JibunKit 0.6.0

ミニアプリ開発向けの基盤を拡張する中間版です。v1.0の共存基準はまだ未達です。
通常IPAに入るミニアプリは引き続きCounterとReminderです。

- **共有background refresh**: 複数Featureの要求をowner/local ID別に永続保存し、一つの
  native refresh IDへ調停するAPIを追加しました。古い実行の完了で新しい要求を消さず、
  各Featureの処理・cleanupが終わるまでnative taskを終了しません。OS受付の失敗と保存の
  成功を区別し、再起動後の未完了要求を復旧します。
- **Package固有の翻訳**: ホストが持たない言語もPackageの標準リソースから選べるよう、
  app/Widgetのmixed-localization設定を接続しました。二PackageのJSONと翻訳を、
  単独・統合・片方を外した構成で検証しています。
- **Package Widgetの接続**: 二つの静的Widgetを一つの標準WidgetBundleへ組み込む手順を
  検証しました。galleryからホームへ追加でき、同じApp Groupから読んだA/Bの値が描画され、
  Aを更新してもBが変わらないことを画像と自動試験で確認しています。

共有refreshの試験は保存・調停・期限・完了の契約を注入schedulerで検証しています。
実OSのpending受付・起動・期限配送は未検証で、バックグラウンドの実行機会や時刻を保証しません。
永続復旧では同じ要求世代が再配送され得るため、Feature側で重複実行に対応する必要があります。
Widgetの証拠は検証した静的Widgetの範囲であり、Controlや任意のSDKの隔離を保証しません。

通常UI 11件とFiles経由のJSON選択復元、共有203試験（既存skip 2件）が成功しました。
本体/Widgetは0.6.0 build 7です。IPAの全37 entryの展開・CRCを確認しています。

- 出荷source: `5e8683f76edbbaeb17a29ed02c1ae6068bc8f759`
- [出荷CI](https://github.com/y-aplus/JibunKit/actions/runs/34684114252) / [検証記録](https://github.com/y-aplus/JibunKit/blob/main/docs/verification/2026-09-12-0.6-release.md)
- IPA SHA-256: `35d04a693e3759b6f4c999b318daedd929e716046b47ea9fde28ad3b61894b1a`
- [IPAを直接ダウンロード](https://github.com/y-aplus/JibunKit/releases/download/0.6.0/JibunKit.ipa)
