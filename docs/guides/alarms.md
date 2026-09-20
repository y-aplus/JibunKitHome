# AlarmKit integration

## Current integration contract

`MiniAppAlarmCoordinator` owns AlarmKit registration identity, durable journal state, operation serialization, reconciliation, and lifecycle participation. Feature code retains typed alarm metadata, presentation, schedule, and business state. Do not flatten those values into a generic timer payload.

Persist intent before native registration, reuse the same identity when retrying ambiguous starts, verify native state after operations, and preserve partial replacement state for recovery. Cold reconciliation must not guess ownership, recreate expired alarms, or delete another feature's alarms. AlarmKit is optional and requires iOS/Xcode support plus real-device validation; the documented 0.8.2 evidence does not cover every Focus or silent-mode condition.

The product API is explicit about partial state. `schedule` journals `.starting` before native registration and commits `.active` only afterward; `retryPending` reuses the identity and UUID. `replace` registers the new UUID first and reports `partialReplacement` with both UUIDs, the failing stage, and original error. `current` validates OS presence under admission and fails closed on multiple usable matches or unknown state. `perform` validates the pre-operation snapshot and confirms stop, cancel, countdown, pause, or resume with bounded snapshot reads rather than treating the native return as an acknowledgement.

`handleSystemIntent` validates admission and the complete identity before business mutation. It does not duplicate OS-standard stop/countdown work and allows a valid stop intent to consume a durable missing-OS callback tombstone; ending rows remain invalid. `reconcile` promotes only known starting rows that exist in the OS, preserves active/missing rows as tombstones, never recreates expired alarms, and quarantines duplicates. `retryEnding`/`endOwned` continue across malformed rows and cancellation failures and remove a row immediately when its alarm is already absent.

Connect `surface(id: "alarmkit")` to `MiniAppContinuingSurfaceGroup`: reconciliation is passive, observation starts one producer only after admission, close drains normal operations before cancelling/draining observation, and open restores admission then observes. Feature state is durable (`MiniAppSharedState`), not `@State` or a process UUID. Configure the singleton synchronously for app/intent cold launch, reconcile before observing, and do not end alarms merely because a screen disappears. Disable/remove closes and drains before OS cleanup; restore never restores old UUIDs or fires expired schedules.

The app needs localized `NSAlarmKitUsageDescription`. Countdown support needs `NSSupportsLiveActivities = YES` plus a widget extension registering the same package's typed `AlarmAttributes<Metadata>`. Do not invent an AlarmKit entitlement; an App Group is for JibunKit shared state/journal, not AlarmKit itself.

## Japanese source notes and historical evidence

状態: **0.8.2で公開済み・採用通常範囲完了**。b1d379bでXcode26.6の独立/統合build・metadata・native2件が成功。5678a41診断版で許可、固定/繰返し/countdown、pause/resume、OS標準stop callback、cold復帰、片側管理/復元とB保持、上書き/Refresh/端末再起動、通常版復帰を確認。Focus/silent条件は独立に試していない。Live Bの単発差分は別途未解決として保持し、実機証拠と31478f2/CI35075825942の実4Feature保持回帰を合わせP2-5採用通常範囲はcomplete。[証拠](../verification/2026-09-16-p2-continuing-surfaces.md)。

JibunKitのAlarmKit境界は、Feature固有の`AlarmMetadata`、表示、schedule、業務状態を型付きのまま保つ。共通coordinatorはowner、local ID、業務世代、registration ID、AlarmKit UUID、操作排他、永続journal、OS集合との照合だけを扱う。汎用timerや任意payloadへ変換しない。

## 製品API

`MiniAppAlarmCoordinator<Native>`は次を提供する。

- `schedule`: `.starting`を保存してからnative登録し、成功後に`.active`へ進める。同じowner/localID/generationのstarting/OS存在activeを二重作成しない。OS不在のactive callback tombstoneは明示的な次回scheduleが同じgate内で除去し、古いIntentを拒否してから新規登録する。
- `retryPending`: native前後が曖昧なstarting行を同じidentity/UUIDで明示再試行する。別UUIDを作らない。
- `replace`: 新UUIDを先に登録する非原子的replace。新active保存、旧ending保存、旧cancelのいずれの失敗も、両UUID、失敗stage、元エラーを`partialReplacement`で返しjournalを保持する。
- `current`: gateと永続admissionの内側でOS存在を検証するasync lookup。unknown stateをusableにせず、複数のusable一致はfail closedする。
- `perform`: active行についてOS snapshotの操作前stateを検証してからstop/cancel/countdown/pause/resumeを許す。AlarmKit呼出しのreturnを成功ACKとせず、boundedなsnapshot再読出しで状態遷移を確認する。
- `handleSystemIntent`: admission、完全identity、systemID、active phaseを業務変更前に検証する。標準stop/countdownはOSが行うのでnative操作を重複実行しない。OSから消えたactive行も永続callback tombstoneとして有効なstop Intentだけが消費でき、endingは兄弟行の有無によらず拒否する。
- `reconcile`: cold launchと`alarmUpdates`で照合する。既知stateのstarting+OS存在だけをactiveへ回収する。active+OS不在はmissing callback tombstoneとして保持し、任意回数のreconcileで削除しない。期限切れアラームは自動再登録しない。重複は診断して古い行をendingへ隔離する。
- `retryEnding` / `endOwned`: 解除retryと管理cleanup。既にOS不在なら成功として行を除去し、不正な一行やcancel失敗があっても残りのowner行を処理する。
- `close/reconcile/endOwned/open` descriptor: `surface(id: "alarmkit")`で親の`MiniAppContinuingSurfaceGroup`へ接続する。`reconcile`はpassiveでproducerを作らない。`observe`は通常gateにadmitされた場合だけ一つのproducerを作る。closeはgateを閉じて通常操作をdrainしてから購読をcancel/drainし、openはgateを開いてobserveする。

`MiniAppAlarmState.unknown`は将来のAlarmKit stateを正常scheduledへ偽装せず、startingをactiveへ昇格させない。未知daemon UUIDも`unknownSystemIDs`へ報告するだけで、ownerを推測したりcancelしたりしない。同じ`AlarmManager.shared`を使うBや同ownerの別namespaceをAの欠落として扱わない。coordinatorはjournalを読むたび全行のownerを検証し、miswired storeならwrite/cancel等の副作用前にfail closedする。

## Feature integration

Featureは`MiniAppSharedState`など永続業務状態を正本にし、admission closureでenabled/maintenanceとgenerationを毎回検証する。画面の`@State`やprocess内UUIDを正本にしない。app/Intentのcold起動でも、Feature singletonは`MiniAppSharedState.shared`と`MiniAppContinuingJournal.shared`から同期的に構成できるようにする。host launchと診断Viewのforeground復帰はdurable stateをreadしてから`reconcile`と`observe`を行い、画面退出だけではOS alarmを終了しない。

Definition factoryは同期の`@MainActor static func makeDefinition() throws -> MiniAppDefinition`とし、次をすべて返す。

- 永続`externalAccess`
- 業務状態だけを対象にした`backup`
- owner業務データの`removal`
- `[service.surface()]`の`continuingSurfaces`
- Feature診断View
- cold host launchでsingletonを構成する`onHostLaunch`

管理・復元の順序は親の`effectiveExternalAccess` / `effectiveRestoreLifecycle`に任せる。disable/removeは受付close、drain、owner OS解除後に業務データを処理する。restoreは古いOS UUIDをbackupから戻さず、再登録もしない。openは受付と購読を戻すだけで期限切れ予定を発火しない。

## fixture products

`Tests/ContinuingAlarms`はapp/extension間のmetadata型同一性を保つため、Feature sourceを各targetへ直接compileしない。

- `ContinuingAlarmSupport`: 型付きconfigurationと永続service helper
- `ContinuingAlarmFeatureA`: `FeatureAAlarmIntegration.makeDefinition()`、`FeatureAAlarmIntents`、`FeatureAAlarmLiveActivity`、`FeatureAAlarmDiagnosticView`
- `ContinuingAlarmFeatureB`: `FeatureBAlarmIntegration.makeDefinition()`、`FeatureBAlarmIntents`、`FeatureBAlarmLiveActivity`、`FeatureBAlarmDiagnosticView`

A/Bはいずれも`localID == "same-id"`だがowner、業務状態、metadata、Intent、Widget、singleton、journalを分離する。Standalone AへB product/Intent/Widgetを混ぜない。Combinedだけが両packageを列挙する。

Widgetは`AlarmAttributes.metadata`がoptionalであることを表示に反映し、`AlarmPresentationState.Mode`のalert/countdown/pausedを別表示する。即時countdownは`countdownDuration`と`schedule: nil`を使い、初版という理由では拒否しない。

## plistとnative検証

app targetには空でない、ローカライズ済み`NSAlarmKitUsageDescription`が必要である。countdownを使うappは`NSSupportsLiveActivities = YES`と、同一Feature packageの`AlarmAttributes<Metadata>`を登録するWidget extensionを含める。AlarmKit専用entitlementを推測で追加しない。App GroupはJibunKitのSharedState/journal共有要件であり、AlarmKit自体の要件ではない。

pure XCTestはjournal段階失敗、pending retry、全replace部分失敗、stale identity、繰返しreconcile後のstop callback tombstone、callback未配送の明示reschedule、ending拒否、既に不在の冪等cleanup、unknown state、passive observer、miswired owner、未知UUID、A失敗時のB保持を検査する。`ContinuingAlarmNativeTests`は実Feature serviceへ誤owner/localID/generation/registrationID/systemIDを渡し、業務bytes不変とDefinition接続を検査する。fakeはAlarmKit実機証拠の代替ではない。

Xcode 26 / iOS 26ではStandalone A、Standalone B、Combined、通常host、Widget、AppIntent metadataをstrict concurrencyでbuildする。実機ではapp単位許可、固定/週次/countdown、pause/resume/stop/cancel、標準stop callback、cold launch、端末再起動、Focus/silent、片側disable/remove/restore失敗後のB保持を確認する。

## Apple一次資料

- [AlarmKit](https://developer.apple.com/documentation/alarmkit)
- [AlarmManager](https://developer.apple.com/documentation/alarmkit/alarmmanager)
- [alarms](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms)
- [Scheduling an alarm with AlarmKit](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit)
- [AlarmAttributes.metadata](https://developer.apple.com/documentation/alarmkit/alarmattributes/metadata)
- [AlarmPresentationState.Mode](https://developer.apple.com/documentation/alarmkit/alarmpresentationstate/mode-swift.enum)
- [WWDC25: Wake up to the AlarmKit API](https://developer.apple.com/videos/play/wwdc2025/230/)
- [NSAlarmKitUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription)


### SDK configuration and concurrency

The native adapter accepts `MiniAppAlarmKitConfiguration<Metadata>`, a Sendable
factory that creates the full typed `AlarmManager.AlarmConfiguration` at the
request site. Capture immutable Sendable Feature inputs and construct the native
configuration inside this closure; do not claim the SDK configuration itself is
Sendable or erase its metadata. This preserves all native options.

Primary declaration checks: [AlarmConfiguration](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration),
[AppIntent](https://developer.apple.com/documentation/appintents/appintent).
