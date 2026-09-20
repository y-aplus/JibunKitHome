# P2-L 初回実装の一括レビュー

> 履歴注記: 本文は初回レビュー時点の指摘と受入条件を保持する。後段の実装・実機証拠を含む現在状態は[plan.json](plan.json)と[status](../status.md)を優先する。

2026-09-16。初回提出Live d731cc6 / Alarm cb00b00を統合したabbf044に対するレビュー。CI投入前の一括修正であり、native未検証のまま合格とはしない。親の管理/復元APIはc95ab52に実装済み。

## 両レーンの共通修正

1. コメントのみのDefinition接続例を実際の接続へ置き換える。同期`@MainActor makeDefinition() throws -> MiniAppDefinition`から、永続externalAccess、removal、backup、continuingSurfaces、診断Viewを提供する。descriptor自体は非同期初期化待ちを必要としないclosureとして作れる。通常host初期化でasyncを同期待機しない。型名はLive `FeatureALiveIntegration` / `FeatureBLiveIntegration`、Alarm `FeatureAAlarmIntegration` / `FeatureBAlarmIntegration`へ固定する。
2. app cold launch/Intentだけの起動でもserviceを構成し、現在の業務世代とOS対応を回復できること。画面の.taskによる初期化や@State/currentIdentityだけを正本にしない。再起動後は既存登録を操作でき、新規開始で重複を作らない。
3. activityUpdates/activityStateUpdates、alarmUpdates等の通常OS変更を受ける購読をapp-ownedで接続する。再照合で重複購読せず、管理で終了/drain、再有効化/復帰で必要な購読を再開する。画面退出でOS活動を終了しない。Taskの自己待機やgate再入のdeadlockを避ける。
4. groupは同ownerの複数native型を許す。journal namespace、surface id、singletonをserviceごとに分離し、同owner別型の登録を「OSにない」と消さない。型の全属性/metadataをidentityだけに制限しない。
5. native fixture XCTestは定数の等値・初期化だけで終わらせない。実fixtureサービスへ古いowner/localID/generation/registrationID/systemIDを渡して業務値不変を確認する等、OS表示を仮装せず誤接続を検出する試験を追加。実機でのみ確かめる許可/表示は未確認のまま区別する。
6. Swift6のthrows/actor/Sendable/SDK宣言を再点検。ガイドと提出は修正後の実APIへ揃える。現時点で未実行のSwift/native検証を成功と書かない。

## Live Activities

- **検証前の業務変更**: A.advance/B.boostはSharedState.update後にcoordinator.validate/requireActiveへ到達する。古いregistrationID、別systemID/localIDでも値が先に増える。coordinatorの同一gate内で完全identity/現OS登録を検証してからFeature変更closureを実行し、typed更新へ渡すAPIにする。native更新失敗時の業務値commitは非原子的な部分成功として明示し、古い入力は業務bytesを一切変えない試験を追加。
- **二重開始**: startは完全identityだけを比較し、診断startは毎回新registrationIDを生成する。owner/localID/generation単位で既存OS/記録を照合し、意図しない二重登録を防ぐ。保存にあるがOS終了済みのものを成功descriptorとして返さない。
- **再照合**: .endingをOSがactiveという理由で.activeへ戻さない。保存済systemIDとOS側identityの対応不一致を修復成功にしない。未知行/重複を診断として返し、解除途中/消失後のretryを閉じる。管理endOwnedは1件のnative失敗で残る所有活動を未処理にせず、失敗記録を保持する。
- **Feature自由度**: `Attributes(continuingIdentity:)`必須は任意の不変属性を渡せない。Feature側attributes factoryまたはtyped requestを受ける。ActivityContentのstaleDate/relevanceScore、標準dismissal .after(Date)を落とさない。Coreの型付きContentをActivityContentまたは同等の型付き完全入力とし、独自固定タイマーへ寄せない。
- **更新の観測**: update後にactive/staleであるだけでは新content反映の証拠ではない。SDKに合わせて内容を観測するか、返却を更新要求の完了として明記し、OS表示反映は別証拠とする。待機後の状態だけで新内容の反映確認済みと書かない。pending/unknownをactive/endedへ勝手に同一視しない。
- A/B surface()の`service()`呼出しはthrowsなのにtryがない。全fixtureの同種エラーをまとめて点検。

## AlarmKit

- **永続受付/世代**: FixtureAlarmAdmissionのgeneration/accepting/stopEventsはメモリのみ。再起動で世代が変わり、currentIdentityも失われる。SharedState等の永続業務状態に接続し、OS Intentのcold起動でも画面configure待ちにしない。DefinitionのexternalAccess/removal/backupを実際に構成する。
- **終了済みの再利用**: stopがone-shotを消した後も.active行が残り、scheduleは同localID行があるため永久拒否する。native absentを照合した終端行を片付け、明示的な次回scheduleを許す。古いボタンの拒否と、OS標準stop直後の正しいcallback配送を両立させる（無条件に全消失を捨てるだけではcallbackを失う）。schedule失敗後のpendingも安全な照合/明示retry経路を持つ。
- **解除の冪等性**: endOwnedで既にOSから消えたUUIDへcancelしてthrowした場合、永久に無効化/削除が失敗する。前後snapshotで既に不在なら完了として扱う。systemID検証・phase保存も各行のtry/catch内へ置き、1件失敗で残りを飛ばさない。retry cancelはending行でも使える。
- **古い置換対象**: exactRecordはphaseを見ないためending/startingの旧登録でもcallbackが業務値を変更できる。通常更新/Intentは適切なactive状態だけ受け、cleanup retryとは区別する。
- **部分失敗**: replaceで新OS登録成功後、active/旧endingの保存がthrowした場合も両IDの復旧情報と非原子的結果を保つ。現在はcancelのdo/catchより前の保存失敗がpartialReplacementから漏れている。元のエラー原因も保持する。active保存失敗・旧ending保存失敗・旧cancel失敗の試験を揃える。
- **unknown OS state**: `@unknown default: .scheduled`は不明状態を正常予定に見せる。unknownを保持するかエラーとして返す。
- **独立/統合の型同一性**: AlarmFeatures.swiftを各app/extension targetへ直接compileすると、metadata/Intentのmodule名がappごとに変わり、appとWidgetのAlarmAttributes型も一致しない。Live fixture同様に安定したSwift PackageのFeatureA/B productへ分離する。product/moduleは`ContinuingAlarmFeatureA` / `ContinuingAlarmFeatureB`、Intent packageは`FeatureAAlarmIntents` / `FeatureBAlarmIntents`、薄いIntentも各Feature所有とし、standalone AへBを混入させない。両者共有のtyped fixture helperが必要なら同fixture配下のsupport moduleへ限定する。
- AlarmAttributes.metadataはoptional。Widgetのreason/routine直接参照を修正。countdown/paused/alertを実際に区別する表示にして、タイマーなのに固定の見出しだけというfixtureを避ける。AlarmPresentation.Alertへ動的Stringを渡すLocalizedStringResource変換も宣言確認。
- native XCTest target/sourceを追加し、アラームの失敗/古いcallbackを実fixtureで検証する。OS許可をCIで強制成功させない。

## 次の提出と親の作業

両workerは本レビューと親APIを含む同じbaselineから修正する。所有pathは初回と同じ。親は通常host診断注入、CI実行ツール、最終統合・試験の実行を行う。上記公開integration型名/product名以外の細部は合理的に決め、一括提出する。CIを子で起動しない。初回1往復の修正として記録し、本質的に未解決なら合格扱いで次工程へ送らない。

## review1後の扱い

Live be4451a / Alarm1160c2eを統合し、Live残件は親で8e307f1以後に補修。Alarmは通知配送と照合回数の競合、closed中の購読、異owner storeの保護に追加修正が必要だったため、同じ担当へ2回目の一括修正を依頼した。これは初回レビューの合格扱いではなく、失敗時保証に残る欠陥の修正。現状とテスト実行有無は[境界記録](../verification/2026-09-16-p2-continuing-surfaces.md)に集約する。

Alarm review2 bc6b99dは67ce68eとして統合済み。親0704ecbでtyped SDK factory・manifest名・試験の待機/JSON安定性も補修した。対象差分のsource reviewを終了し、Swift/native CIへ進む。未実行のテスト合格は主張しない。
