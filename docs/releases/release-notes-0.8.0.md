# JibunKit 0.8.0

P0の基本契約を維持し、P1全6単位の通常接続・検証・利用手順を揃えた版です。前の正式公開版は0.7.0。1.0は未達で、対応範囲の最終判断は別に行います。

## 変更

- OS共有シート・Filesの入力を受信先Featureへ保存し、本体の「受信」から取り込めます。取消、再起動保持、失敗後の冪等再試行、対象ownerだけの削除を接続しました。文字列の形式読込みと初回保存先の誤拒否も修正しました。
- Package内App Intents/entity候補と静的Widgetを、通常保存・無効化・削除へ接続する手順と検証を整えました。既存Counterの識別子は維持しています。
- 通知添付の原本を保持する一時コピーと、登録・取消・削除時の寿命管理を追加しました。Feature別の前景表示、通知操作・文字入力返信を確認しました。
- HTTPの専用Cookie・パスワード資格情報・cache、停止後logout・管理削除を接続しました。`MiniAppFeatureLifetime.withStoppedOperation`で後処理の実終了まで再開・管理を調停します。
- WebViewのCookie/localStorage/IndexedDBとOS Web認証を通常Featureへ接続し、片側取消・削除時の他方保持を確認しました。

通常IPAにはCounter/Reminderと汎用Share Extensionを含みます。独自の受信先には`incoming`登録が必要です。診断A/B Feature・Records・個人用Zaikoを通常IPAへ追加するものではありません。

## 検証と配布物

0.8.0/build10の製品sourceは`71ef1ffb4f84442bf8853c0c2e286c2bedd81d22`。[CI34967147135](https://github.com/y-aplus/JibunKit/actions/runs/34967147135)で共通273件（skip2、失敗0）、Records11件、通常Release/metadata/署名/IPA検査が成功しました。

IPAは2,243,242 bytes、SHA-256は`50626937264c8cb4cef7193f1c3035e06e1dc1cc1a5d6d1faf2f3fbd80cf6ff6`。全ZIP entryのCRC、本体/Widget/Shareの版・ID、診断kind/resource非混入を確認しています。

実機は6beb877の通知/HTTP/Web・通常Shortcutsと、4e6a3f4（0.7.1/build9）の共有/Files・Shortcuts取消/失敗・Widget・更新/Refresh・通常版復帰を確認しました。4e6a3f4から製品の版のみを変更したため、旧sourceを保持して実機証拠を再利用しています。新0.8.0 IPAそのものを再度実機確認したという意味ではありません。

通常UI13件/Files JSON復元、生成host、独立Packageのmetadata/Widget、対象native試験はsource別の既存証拠を差分照合しました。本runで全Simulator試験を再実行したとは扱いません。[全条件・文書監査・公開確認](../verification/2026-09-15-0.8-release.md)を参照してください。

## 残る制約

Featureは自身の保存・寿命・管理への接続を所有します。同一process内の強制隔離、任意DB/SDK/extensionの透過統合、HTTP cacheの永続保持、全SSO、Widget即時更新は提供しません。

共有の失敗直後の未取込み行は独立した実機観測なしで、CIの保持確認と分けています。Widget再登録後は上書き/Refreshで起動保持を確認しており、単純再起動だけの再試験とは区別します。通常版復帰後に診断Widgetの旧表示が残りましたが、コード除去はホームの配置や所有データの削除を保証しません。

Spotlight解除の過去のSimulator遅延原因は未確定です。実機の初回無効化は体感ほぼ即時で成功しました。集中モード下の通知配信、Siri音声呼出しは確認済み範囲へ含めません。

P2/P3の残件は[台帳](../coexistence-ledger.md)へ維持し、[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)を踏まえた1.0正式境界を0.8.0完了時に決定します。
