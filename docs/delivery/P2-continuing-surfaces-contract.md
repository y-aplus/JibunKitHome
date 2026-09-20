# P2-L: Live Activities / AlarmKit の実装境界

> 履歴注記: 本文はP2-L開始時の契約であり、冒頭以下の未完了表現は当時の状態である。現在は採用通常範囲をcompleteと判断済みだが、Live Bの単発差分など未解明条件は保持する。[plan.json](plan.json)と[status](../status.md)を優先する。

2026-09-16開始。0.8.1公開後の製品baselineは88ab7cb、文書/公開照合済みmainは4af35e5。次の0.8.2目標はP2-5（D28）の通常範囲。まだ実装・署名条件・実OS検証が完了したわけではない。

## 最初に揃える責任

Featureは活動の属性/表示/業務状態、アラームの意味・予定と操作内容を持つ。基盤はowner別の操作権限、OS登録との対応、再起動照合、管理/復元時の後始末と他Feature保持を補う。既存MiniAppID/Context・Intents・管理・Runtimeを再利用し、汎用タイマー/通知業務モデルへFeatureを押し込めない。

- appが非選択/背景になっただけではOS上の継続活動を終了しない。Runtimeの画面内Task寿命とOS活動の寿命を混同しない。
- 開始/更新/停止の入力はowner、Feature local ID、必要な世代/OS identifier、Feature所有payload。別owner/不明ID/削除前世代を推測で配送しない。
- 開始失敗/権限拒否/保存失敗/取消は成功扱いせず、Aの失敗でBを更新・削除しない。OS登録と保存の途中終了で再接続可能な範囲を説明する。
- cold launch後は既存OS登録と保存を照合し、二重登録やownerの取り違えを避ける。OSが終了したものを無条件に復活させない。
- 無効化/削除では新規受付を止め、当該ownerのOS活動と更新購読を片付ける。管理完了をOS解除前に表示しない。OS失敗は既存管理の未完了/再試行へ接続する。
- 復元で古い操作が新しい業務データを変更しない。保存値の復元とアラームの再登録/通知発火は別の判断であり、暗黙に期限切れ予定を大量再発火しない。
- 共通CoreはActivityAttributes/AlarmMetadata等の任意Feature型をhost内switchで列挙しない。必要な登録は標準型とFeature側adapter、optional接続で提供する。

## 分担と初回提出

最大3レーン。親はCoreの共通契約、MiniAppDefinition/Registry/Runtime/管理/復元、Project/Package/CI、最終ガイドと実機/出荷を所有する。実装前のnative API/署名条件と契約確認を二つのCLI sol/lowワーカーで並行する。権限/sandbox設定を上書きせず、サブエージェントやChat機能へ変更しない。

- Live Activitiesレーン: `docs/delivery/P2-live-activity-design.md`のみ所有。ActivityKitの型、request/update/endとactivityUpdates/state、cold reconnect、interactive Intents配送、OS上限/拒否、plist/entitlement/署名条件を一次資料と既存コードで整理する。API案とA/B検証fixture/通常host接続案を一括提出する。
- AlarmKitレーン: `docs/delivery/P2-alarm-design.md`のみ所有。schedule/update/stop/cancel、authorization/metadata/Intents、永続OS照合、管理と復元、OS/署名条件を同じ粒度で整理する。API案とA/B検証fixture/通常host接続案を一括提出する。
- 初回は設計と最小native呼出し例を文書へ提出。製品コード/共有ファイル/CI/pushは変更しない。Windowsで実行していないSwift/Xcodeを検証済みにしない。未確認の有料登録制限を事実として扱わない。

二提出を受けて親が共通契約とAPI/担当pathを一度固定し、独立実装を同じbaselineへ渡す。ネイティブ動作の違いが判明する前に共通abstractionや管理APIを別々に実装しない。子ごとのCIは回さない。設計phaseを実装完了とは扱わない。

## CIと実機

P2-L初回実装予算2run。初回の同一sourceで独立/統合native build・metadata、共有owner/復旧試験と通常接続をまとめる。各job見込み25分以内、上限30分目標。実際の入力/filter/再利用sourceと準備/upload込み見積りは提出統合後・投入前に固定する。必要なら二native jobを同じrun内で並列化。署名条件を含む最小native比較を先行する必要がある場合も予算を記録し、実装/CIの分散投入で回数を隠さない。

実機は開始/更新/終了、二ownerの同時利用、OS上の操作配送、アプリ/端末再起動、片側拒否/取消/無効化/削除、通常版への復帰と既存データ保持を一括する。採用する署名/OS構成で動かない箇所は、同条件の独立アプリ比較とAPI/署名根拠を示し、複雑だから未実装という理由と区別する。3失敗までに切り分け、待機はOS通知に任せる。

## 親の通常host接続レビュー（初回並列設計中）

既存sourceを読み、現時点では下記を実装上の条件とする。共通API追加の決定やnative挙動の実証ではない。

- NotificationAppDelegateは管理状態を初期化した後、全Definitionの同期onHostLaunchを呼ぶ。disabledを理由に必要なnative登録を抜かない設計だが、業務的な再登録/開始は別の受付判定が必要。asyncのOS照合を同期callback内で待機しない。長寿命の更新購読はFeature/host所有のTaskとして保持し、解除・再開始と接続する。
- 通常管理は保存済み状態/起動受付→externalAccess.close→lifetime.stop→owner予約→onUnregister→通知/Spotlight解除→必要ならremoveDataの順。OS活動の停止は既存onUnregisterへ接続できる候補。ただし非選択だけで活動を終了するRuntime cleanupは不適切。再有効化は開始許可だけを戻し、過去活動の再発火を暗黙に行わない。
- effectiveRestoreLifecycleはFeature指定のrestoreLifecycleまたはlifetime.restoreLifecycleをexternalAccessのrestoreで囲む。OS登録/操作識別子をバックアップpayloadそのものに復元して古い登録と衝突させない。古いOS活動の終了と新業務データへの操作配送は世代境界で扱う。失敗した停止はrecoverAfterFailedStopと既存未完了状態へ接続する。
- MiniAppSharedState.read/updateは無効・maintenance中を拒否する。したがって管理が受付を閉じた後のOS後始末が通常readへ依存すると失敗する。管理用の所有登録一覧をどこから読むか、永続の最小対応表を分離するか、限定された保守用読取りが必要かを両native案と一度照合して決める。単にenabledを一時的に戻す解決はしない。
- MiniAppSharedState.updateのclosureは同期で、native async request/update/endをNSFileCoordinatorの保有中へ入れない。OSと永続表を原子的にcommitできると仮定せず、途中終了の段階と再照合/重複拒否を検証する。Featureコード全体の強制隔離は保証しない。

両CLIワーカーは同一baseline bcfde0dで起動済み。実行記録からsol/low、承認never・full accessが既定で継承されたことを確認し、起動時の権限上書きは行っていない。履歴IDと監視設定はローカル運用記録へ保存。完了時の一回通知を登録済みで、定期的に進捗を読み返さない。

## 実装契約の固定（2026-09-16、両設計レビュー後）

設計提出は c0ed629 までに統合した。以下は両提出の提案より優先する。共通宣言の初版を製品sourceへ追加したが、WindowsではSwift未コンパイル。子ごとにCIは投入しない。

- 共通identityは `MiniAppContinuingIdentity(owner: MiniAppID, localID: String, generation: UUID, registrationID: UUID)`。保存上ownerはString。世代はFeature業務データの世代、registrationIDは同世代内の作り直しも分離するUUID。Intentは全identityと必要なOS IDを照合する。
- `MiniAppContinuingJournal(owner:namespace:containerURL:)` の `read()` / 同期 `update` をOS対応表に使う。登録はidentity/systemID?/phase(starting,active,ending)。業務データのbackupには含めない。管理中も読み書きできる。OS呼出し前にpendingを永続化し、失敗・中断で記録を失わない。異なるowner/namespaceの更新は禁止。未知OS登録は診断対象で、推測で他ownerへ配送・削除しない。
- `MiniAppContinuingOperationGate` はアプリprocessでの直列化を担当。通常 `perform`、管理 `close`（進行中をdrain）、`performMaintenance`、`open`。actorの再入だけを排他と誤認しない。singleton serviceをowner/native種別ごとに共有し、extensionで別gateを作ってOS開始しない。LiveActivityIntentはapp実行。通常operation内でFeature提供のadmission/世代検証を必ず行う。gate/journalだけで任意Featureコードの強制隔離を保証しない。
- `MiniAppContinuingSurface(owner:id:close:reconcile:endOwned:open:)` をadapterが提供。Definitionの `continuingSurfaces: [MiniAppContinuingSurface]`、effectiveExternalAccess/restore、host起動/再開接続は親が実装する。closeは受付閉鎖/drain、endOwnedは管理中でも動く冪等OS解除、reconcileは再照合であり暗黙の再登録をしない。画面のtask終了と無関係。失敗はthrowで残す。openだけで過去の活動を再開しない。
- native非同期終了は無期限待機にしない。ActivityKit end(.immediate)後は終了/消失の観測とOS画面の消失を区別し、boundedな未収束を再試行として扱う。OSが無効化後に業務操作を実行できないことを優先し、確認していないdismissedの必達を仮定しない。
- Alarmの同一ID再scheduleやatomic replacementは保証しない。代替新規→旧解除を採る場合は部分成功と両IDを残し、即時countdownも「初版だから禁止」とせず非原子的な結果を正直に返す。固定/繰返し予定・countdown・pause/resume/stop/cancelをnative APIの意味のまま扱う。期限切れ復元の自動再発火は禁止。
- Alarm authorizationはOS上app単位である。AだけOS許可を拒否してBは許可済みという試験は不正確。Feature別受付拒否とapp全体OS拒否を分離する。
- 既存最低OSは26。iOS25 fallbackの追加は不要。通常local Live Activityを本境界で実装し、APNs経路は後続P2-Bと接続する。OSの型付きpayload/表示自由度を削らない。

所有path:

| レーン | 実装・検証・文書 |
|---|---|
| 親 | 上記共通3ファイル、Definition/Registry/管理・復元・host起動、Package/Project/CI/Tools、共通試験、統合diagnostic注入、台帳/出荷 |
| Live Activity | Sources/JibunKitCore/LiveActivities/、Tests/JibunKitCoreTests/LiveActivities/、Tests/ContinuingLiveActivities/（FeatureA/Bのnative display/Intent/diagnostic Viewとfixture）、docs/guides/live-activities.md |
| Alarm | Sources/JibunKitCore/Alarms/、Tests/JibunKitCoreTests/Alarms/、Tests/ContinuingAlarms/（FeatureA/Bのnative display/Intent/diagnostic Viewとfixture）、docs/guides/alarms.md |

両子は共通baselineの宣言を変更せず、typed native adapterからFeature固有表示・Intentまでと失敗試験をまとめて提出する。共有Package/Project/CIや通常Registryは変更せず、必要なtarget/source/plist/metadata/host wiringをworkの提出へ列挙。各fixtureは独立A/Bと統合を同じsourceで構成可能にする。Swift未実行を隠さず、根拠のあるAPIを使いcompile未確認を明示する。初回提出と一括レビューで揃えてからnative CIを行う。
