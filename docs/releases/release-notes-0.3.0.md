# JibunKit 0.3.0

ミニアプリごとの通信・実行処理・画面状態の所有権を整える、開発者向けの中間版です。**1.0の共存基準はまだ未達です。** 通常IPAはCounterとReminderを含み、Recordsは参照ソースとして提供します。ZaikoとCI専用Featureは配布IPAに含みません。

## 主な変更

- Feature/profile別のURLCache、Keychain、Cookie、HTTPパスワード資格情報の明示保存を追加。同じサーバー・アカウント名でも状態を分け、個別ログアウトが他ownerへ波及しない経路を検証しました。
- FeatureのTask受付停止・取消・完了待ち・非同期資源解放をRuntimeへ接続。URLSessionの要求とdelegate終了を待ってから保存・削除する部品を追加しました。
- 復元のstop/apply/resume、重複復元とsnapshotの調停、途中取消・失敗段階の報告を追加しました。
- 通知カテゴリの所有者別合成・更新・解除、foreground方針、action配送、所有者限定の一括取消を追加しました。
- host活動状態の配送、idle timerの取得/解放、Feature/profile別Webデータストアの割当を追加しました。
- ウィンドウごとにnavigation状態を所有し、process通知は一つの登録画面へ配送する構造へ変更しました。

接続例: [通信状態](https://github.com/y-aplus/JibunKit/blob/main/docs/network-integration.md)、[Runtimeと復元](https://github.com/y-aplus/JibunKit/blob/main/docs/runtime-restore-integration.md)、[画面状態](https://github.com/y-aplus/JibunKit/blob/main/docs/scene-navigation.md)。これらの部品を各Featureの所有者へ明示的に接続して使います。未接続の共有singletonを自動的に隔離する仕組みではありません。

## 導入と互換性

添付IPAをSideStoreで署名して導入します。更新前にバックアップを保存してください。本体/Widgetのbundle ID、App Group、Counter/Reminderの保存キーは維持しています。配布版は0.3.0 build 4です。開発中IPAの1.0.0表記から、実際の公開段階に合わせた番号へ戻しています。

## 検証範囲と残件

macOSの実HTTP試験で、同一serverへのCookie/認証/cacheの分離、profile別再生成、個別logout、遅い応答と取消後の保存・削除順序を確認。iOS SimulatorではCookie/HTTPパスワードのprocess再起動と他Feature保持、二navigation実体の非干渉、実通知遷移を確認しています。検証source・CI・IPAの対応は[公開記録](https://github.com/y-aplus/JibunKit/blob/main/docs/verification/2026-09-10-0.3-release.md)を参照してください。

この公開版そのものの実機確認は未実施です。別sourceではユーザーがJSONバックアップの書出し・読込み・対象選択・上書き復元を確認しています。SimulatorのFilesからJSONを選択するUI試験は未解決で、今回の限定UI試験を全回帰成功とは扱いません。

Cookie/パスワードの保存は明示操作で、自動保存、全Cookie属性、証明書/SSO、background再接続は未完です。Webデータの再起動保持には過去にCIで不安定性があり、全Webデータ・強制終了耐性を保証しません。二navigation実体の試験はOS上の複数window操作を実証したものではありません。

音声・バックグラウンド・一般callback・capability合成なども開発中です。[差分台帳](https://github.com/y-aplus/JibunKit/blob/main/docs/coexistence-ledger.md)で仕様確認・比較実験・設計検証の残りを追跡します。namespaceは同一process内のセキュリティ隔離ではなく、正しく接続したFeatureの意図しない競合を減らすための所有権境界です。

## 配布物

- Source/tag: `7954dda246fa5d711371ad2223b42a2429bf4868` / `0.3.0`
- 出荷CI: [34442458523](https://github.com/y-aplus/JibunKit/actions/runs/34442458523)（成功）。共有114テスト、独立Feature 9テスト、生成Feature検証、Records単独ビルド、本体/Widgetビルド、署名構造・App Intents・IPA検査を通過。
- このrunではSimulator UIは実行せず、実装差分のない直前source `6a4d2fd` の限定UI試験 [34440565104](https://github.com/y-aplus/JibunKit/actions/runs/34440565104)を参照しています。
- [IPA直接ダウンロード](https://github.com/y-aplus/JibunKit/releases/download/0.3.0/JibunKit.ipa): `JibunKit.ipa`、793,280 bytes、全26 ZIP entryの展開/CRC成功。
- SHA-256: `afe51e1d7b2cf025913ed404ae24fc1a0955e49d8f08f918112195936f56e0c9`
