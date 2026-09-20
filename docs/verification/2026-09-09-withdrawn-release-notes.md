> 公開保留: 2026-09-09に1.0未達と再評価。以下は旧候補の記録であり、公開承認の対象ではない。

# JibunKit 1.0.0

独立したSwift/SwiftUI Featureを単独アプリとJibunKitの両方で開発するための基盤です。通常IPAにはCounterとReminderを含みます。Recordsは複数画面・構造化データ・添付・個別通知を持つ参照Featureとしてソースを提供します。Zaikoは含みません。

## 主な変更

- TuistとXcodeによるビルドへ移行。独立Swift Package、Example App、UIテストの雛形を提供。
- Featureごとの保存先、JSON/添付付きZIPの選択バックアップと復元、上書き確認、部分失敗報告を追加。
- UUIDなどFeature所有の詳細識別子をURL・通知から渡す接続と、記録ごとに独立した通知IDを追加。
- Recordsで編集・検索・添付・schema移行・通知・復元の責任分離を例示。

## 導入と更新

添付のJibunKit.ipaをSideStoreで署名して上書き導入します。先にバックアップを保存してください。Counter/Reminderのbundle ID、App Group、保存キーを維持します。WindowsからはGitHub Actionsで独自Featureを含むIPAを作れます。[ビルド手順](https://github.com/y-aplus/JibunKit/blob/main/docs/build.md)と[追加手順](https://github.com/y-aplus/JibunKit/blob/main/docs/mini-apps.md)を参照してください。

## 検証と制限

1.0候補の全CI（34311268444）でビルド、App Intents metadata、Widget、単独Featureとホスト共存、バックアップ往復、通知遷移、Records編集・添付保持を確認。Records接続版では2026-09-09にユーザーが上書き・署名更新・保存維持・Widget/Shortcuts・複数通知の詳細遷移・取消・選択復元を確認しました。通常配布IPAへRecordsは登録していません。

SimulatorのQuick Look表示assert一つは既知の期待失敗です。実機での添付プレビューは中間確認で成功しています。実機確認版と通常配布物のsource・差分・hashは[検証記録](https://github.com/y-aplus/JibunKit/blob/main/docs/verification/2026-09-09-v1-candidate.md)で区別します。

全Featureをまとめた原子的な復元は保証しません。保存形式やDBの整合性はFeatureが所有します。OS通知予約はバックアップに含めず、Records復元後は再設定します。Feature間のnamespaceはセキュリティ隔離ではありません。署名・OS由来の権限制約を解除する仕組みではなく、任意IPAの動的読込みにも対応しません。

公開時に配布source、最終CI URL、IPA SHA-256をここへ追記します。
