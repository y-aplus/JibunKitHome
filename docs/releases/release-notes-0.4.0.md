# JibunKit 0.4.0

Featureごとの画面・保存・通知の共存と、nativeビルド設定の統合を進めた開発者向け中間版です。**1.0の共存基準は未達です。** 通常IPAはCounterとReminderを含み、Recordsは参照ソースとして提供します。

## 主な変更

- ミニアプリを切り替えても、それぞれの値ベースの画面経路を保持。sceneの活動・選択状態の通知と、その状態に従う任意の自動ロック抑止を追加しました。
- 通常の保存操作と復元/snapshotを調停し、復元前の停止が途中で失敗した場合の回復callbackを追加しました。SQLiteの実操作と他Featureの継続を検証しています。
- Foundation NotificationCenter購読と、UIKitの短時間バックグラウンド実行tokenをFeature/Runtime単位で管理します。OSの実行時間枠はhost全体で共有します。
- Core Spotlightの項目を所有者別に登録・削除し、検索結果から所有Featureの詳細へ配送。別Featureの経路保持と、アプリ終了後の起動を検証しました。
- 通知action/foregroundの所有Featureへ元のnative requestを渡し、独自userInfoやcontent/triggerを取得できるようにしました。
- FeatureのInfo.plist・entitlements・言語別InfoPlist.stringsをtargetごとに合成。衝突を検出して明示解決し、生成した設定と実際のapp/Widget bundleをCIで比較します。
- WebKitのCookie・localStorage・IndexedDBについて、二Featureの分離、再起動保持、片側のnative削除後の他側保持を検証しました。

## 導入と検証範囲

IPAをSideStoreで再署名して導入します。本体/Widgetは0.4.0 build 5。本体/Widgetのbundle ID、App Group、Counter/Reminderの保存キーは維持しています。Zaikoと検証専用Feature、実機確認待ちのKeychain access-control拡張は含みません。

各単位の検証は[差分台帳](https://github.com/y-aplus/JibunKit/blob/0.4.0/docs/coexistence-ledger.md)、出荷source・配布IPAの対応は[公開記録](https://github.com/y-aplus/JibunKit/blob/main/docs/verification/2026-09-11-0.4-release.md)を参照してください。[出荷CI](https://github.com/y-aplus/JibunKit/actions/runs/34531391110)では通常UI 11試験と、Files経由のJSON選択復元を含む出荷検証が成功しました。

[JibunKit.ipaを直接ダウンロード](https://github.com/y-aplus/JibunKit/releases/download/0.4.0/JibunKit.ipa)（927,368 bytes）。SHA-256: `7a96190defae0991eba5a94ef2a185ee02800e7ac042ede2521961ecbb4ad6b0`。出荷sourceは`d22341646e111a6487f8f49ca791320f013bffd3`です。

Feature作者が各部品を所有者へ接続して利用する開発環境です。同一processをOSの別アプリ相当に隔離するものではありません。OS上の複数window、音声/captureなど共有資源、一般callback等の補完は継続中です。実権限grantや署名による利用条件は、ビルド設定の合成とは別に確認が必要です。

この版のIPA自体の実機確認は未実施です。Records/生成Featureの専用UI試験は今回の出荷CIでは実行せず、個別の過去CIを根拠としています。SimulatorのRecords Quick Lookは既知のexpected failureを残し、previewの成功には数えていません。
