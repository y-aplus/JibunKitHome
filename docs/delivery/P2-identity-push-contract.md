# P2-I: 外部データidentityとPush配送

## 2026-09-19 採用境界の変更（ユーザー確定）

無料署名で自作アプリを運用する製品目的に対し、有料署名・container/provider設定を要するCloudKit/APNsを通常利用の前提にしない。既存実装は条件を満たす利用者向けの任意機能として残し、実CloudKit通信・APNs登録/配信の検証を1.0必須条件から外す。実通信は未検証であり、この判断を成功証拠に置き換えない。無料署名の標準構成はこれらを要求しない。

汎用HTTP等による外部データ同期、owner/account/localIDの分離、停止・管理・遅着拒否は引き続き通常範囲。署名専用の実通信条件だけの変更であり、外部同期全体やローカル通知を除外しない。以下の旧契約・投入履歴は、この変更と矛盾する範囲では当時の記録として読む。


2026-09-18開始。P2-8/D30とP2-10/D14,D26。P2-B背景/位置の実機残件とは独立に進める。ユーザーは約8時間不在、iPad確認は起床後以降。iOS継続処理code1の追加追究は停止。背景URLSessionの背景callback/保存/完了はf6f6c04で実機確認済み、終了後cold起動とは区別する。

## 共通契約

通常のFeature定義・MiniAppID/Context・FeatureLifetime/Runtime・管理/選択復元・既存宣言合成を再利用する。二ownerで同じローカル識別子、A停止/削除/復元・B非初期値保持、世代の遅着、account/token変更を検証する。独立アプリなら得られる境界との差分を補い、汎用同期backendや全認証方式の一般化は作らない。OS/署名/外部server条件と未実装を区別する。

ワーカーは実装・試験ソース・手順をまとめて提出する。CIは実行しない。親が二提出の契約を照合して一つのCI境界を固定する。初回予算3run、3失敗までに原因を切り分け。途中commitはCI起動条件ではない。親はhost/manifest/workflow、台帳・出荷文書、統合fixtureの接続を所有する。元のC:/Dev/JibunKitとignored Zaikoは変更しない。調査は必要なApple一次資料を参照するが別の研究タスクへ広げない。

## 外部identity担当

所有path: Sources/JibunKitCore/ExternalIdentity/、Tests/JibunKitCoreTests/ExternalIdentity/（実際の既存testsディレクトリ構造に合わせる）、Tests/P2Identity/、docs/guides/external-data-identity.md、docs/delivery/P2-identity-submission.md。

container/account/dataの所有境界を明示するAPIと通常Feature接続。CloudKitの標準型・record zone/record ID/subscription等の名前空間、account変更時の旧世代/取消/結果隔離、Aの削除/復元でBを保つ範囲を実装する。任意containerの自動移行や業務sync engineは作らない。native CloudKit接続を含み、署名/entitlementなしの診断hostを起動だけで落とさない。利用可能な構成の事前条件を明示し、注入backendの成功を実CloudKit通信成功と呼ばない。Tests/P2Identity/P2IdentityProbe.swiftに二つのMiniAppDefinitionを公開し、P2IdentityNativeTests.swiftで所有/遅着/account変更/失敗/復旧を検証する。共通hostへの追加は親が行う。

## Push担当

所有path: Sources/JibunKitCore/RemotePush/、Tests/JibunKitCoreTests/RemotePush/（既存test構造に合わせる）、Tests/P2Push/、docs/guides/remote-push.md、docs/delivery/P2-push-submission.md。

app単位APNs tokenとFeature/server identity、登録失敗・token更新・owner解除・世代遅着、正しい通知/背景配送とcompletion集約を実装する。既存通知router/外部routeと統合し、payloadのownerを全Featureへbroadcastしない。server別業務処理はFeature所有。必要なnotification service/content extensionは通常範囲の採否と接続案を示す。汎用backendは作らない。Tests/P2Push/P2PushProbe.swiftの二MiniAppDefinitionとP2PushNativeTests.swiftを用意する。UIApplicationDelegateへの具体的な呼出し/署名条件は提出文書へ示し、host/Project.swiftを直接編集しない。実APNs登録成功や配信は署名/server条件付きでありfake callbackと区別する。

## 親の並行作業と検証境界

親は既存通知delegate/宣言合成とCloudKit/APNs署名条件を確認し、二fixtureの使い捨てnative host、全method照合、通常host回帰をまとめる。提出前の重複実装はしない。契約の根幹が変わる問題はまとめて報告し、細かなAPIごとの承認待ちにはしない。CIの正確な入力/filter/時間上限はソース統合後に追記する。

## 開始・親の準備

2026-09-18、JibunKit project `62ddf945-4896-42c1-8418-1721140ee140`を指定してSol lowの別スレッド2本を作成。基点7347b483936e7f8bfe45d36984c32390cdcae2b3、identity/pushの両worktreeで担当sourceの作成を確認。サブエージェントではない。親は`codex/p2-identity-push`へ分岐し、P2-Bの実機残件と分離した。提出完了時に親へ一回通知し、CIはワーカーから起動しない。

親はidentity-push用の使い捨てhost生成と既存native検証へのsurface追加を準備。host生成は本体/Widget/Share IDと通常Featureを保ち、2fixtureとnative test targetを組み込む。途中に欠落・test混入・anchor不一致があれば書込み前に拒否する。fixture未提出の現段階は最小の入力を使う生成試験3件と既存media/background/workflow検査7件が成功しただけで、実Swiftソース接続/iOS成功は未確認。実提出後に同じ生成・全method試験を通す。

診断にはremote-notification background modeのみ追加し、APNs/CloudKit entitlementやcredentialを偽造しない。[APNs登録](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns)はapp/device固有tokenと正しい署名を要し、[CloudKit container](https://developer.apple.com/documentation/cloudkit/ckcontainer/init(identifier:))は指定containerのentitlementを要する。通常hostは明示的に機能を組み込むまでOS登録/CloudKit生成を行わず、署名がない状態で起動を落とさない。実native APIとfake配送の試験を区別し、未署名CIからserver同期/APNs配信の成功を主張しない。

## Push初回レビューとhost接続

Push初回a1315db/12f7523を受領し開発branchへ統合、CI前の一括修正を同じ担当へ返した。closed/concurrent接続のrollback、generation付き解除、Runtimeによるhandler取消/join、遅いtoken通知と登録失敗後の同値token回復、同期cold owner登録、completion ticketの保持、ネスト/null payloadの非劣化をまとめる。初回契約の通常停止/復帰/世代保証を満たすための修正で、CIを先行投入しない。親の担当メッセージは初回2件＋Push修正1件、レビュー往復Push1/identity未提出。

親は本体UIApplicationDelegateのtoken/失敗/背景payloadの3callbackを接続。受信前に既存managementとlaunch失敗gateを確認し、既知の許可ownerだけcoordinatorへ送る。OS登録要求はbuild-time `JibunKitRemotePushEnabled=true`の明示設定で起動時に行う（正しいaps-environment/profileを代替しない）。通常構成と署名なし診断は未設定なのでOS登録を自動実行しない。通知の表示許可とAPNs登録資格は同義ではない。

親所有Tests/P2IdentityPushHost/HostNativeTests.swiftは実delegate→coordinator→通常Featureの配送、無owner/無効owner拒否、B非初期値保持、callback一回とtoken転送を対象にする。2担当のnative全methodに加えて同じschemeで実行。未提出の最終APIに合わせた照合とSwift実行は今後。

## identity初回レビュー

identity初回a5bf420/550cd74を統合し、同じ担当へ一括修正。管理の停止後削除でcurrent消失によりinactiveとなる問題、並行activate/closed runtimeの世代rollback、operation取消/joinとserver commitの限界、通常CloudKit上書き、永続keyとactivation世代の分離、CKAccountChangedのFeature所有observer、署名専用試験と通常CIの分離を対象にした。実管理/停止/復元を通る試験へ補強する。現時点の親担当メッセージは初回2＋各修正1＝4件、修正往復各1。初回契約の通常利用/失敗保証が提出で不足していたためで、CIで発見して再実行する前にまとめて修正する。

両初回ソースが揃い、親のhost生成試験を最小入力から実提出fixtureへ切り替えた。これはソース配置/構成検査でありSwift compileやOS通信の成功ではない。統合branchは未検証でmainへは入れない。署名CloudKit roundtripを通常native全methodへ混ぜないよう、担当の分離修正を待って全件数を固定する。

## 統合後の検証境界

両担当の修正を統合。各2往復（初回の寿命/管理修正、追加のアカウント切替時削除・JSON整数保持）をCI前に完了した。親からの担当メッセージは計6件。親は実delegateの同期token転送と、画面を開かずcold ownerへ配送するhost試験を追加。ローカルhost生成/検証回帰11件が成功。Swift/iOS成否はCI前なので未確認。

`docs/verification/2026-09-18-p2-identity-push-evidence.json`で事前範囲を固定する。同一SHAで通常/shared（全共有試験、Records、通常IPA、Search UI）とidentity-push native（全12method、署名専用CloudKitを除く、診断Release IPA）を2run並列投入する。前者24分/後者22分見込み。直近通常18分06秒/native12分48秒を準備・upload込みの基準に余裕を加えた。初回予算3run内で、再試行前は原因と対象を記録する。

今回のnative成功だけではAPNs実配信/CloudKit実通信完了にしない。正しい署名・container・providerが必要な確認は別に残す。P2-Bの未確認も閉じない。ユーザー睡眠中に実機操作を求めない。


## 変更後の出荷gate

`plan.json` の `P2-8.signed-service` / `P2-10.signed-service` だけを `approved-unverified` とする。報告書は同じscope/reasonを持つ `approved_unverified` 記録を必須とし、結果は `unverified-approved-exclusion` に固定する。除外項目をpassed evidenceへ混ぜること、一般のownership/integration/device/docsへ同じ免除を付けることは拒否する。既存source時点の報告書は当時の計画に対する履歴であり、新しい最終報告書では変更後の記録を用いる。

親統合後のdelivery positive/negative試験21件とplan検査が成功。通常構成の代表証拠の最終照合は残し、P2-8/P2-10をこの承認だけでcompleteへ変更しない。

親の最終照合で、6beb877のHTTP/通知実機記録と対象ファイルの差分なし、c4703a1のidentity/push/host差分なし、後続管理変更のCI35357260854/35365770330を確認した。旧報告の「Sources全体が不変」という記載は当時の境界へ限定し直した。新最終reportはci stageとdelivery21試験に成功し、採用通常範囲をcompleteとした。署名専用実通信未検証と正式release文書監査は引き続き別扱い。
