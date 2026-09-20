# P2-L ActivityKit / Live Activities 契約案

> 履歴注記: 本文は製品実装前のAPI提案であり、未実施表記は当時の状態である。現在の採用範囲・検証状態は[plan.json](plan.json)、[status](../status.md)、[Live Activitiesガイド](../guides/live-activities.md)を優先する。

更新日: 2026-09-16。対象 baseline: `bcfde0d88c19a143620b16e71230e4fb404ae7f1`。これは API shape の提案であり、製品実装、Xcode build、署名、Simulator/実機確認は未実施である。この Windows 環境には Swift/Xcode がない。

## 結論と責任境界

Live Activity を汎用タイマーに抽象化しない。Feature は固有の `ActivityAttributes`、`ContentState`、表示、業務上の開始/更新/終了条件と interactive action を所有する。JibunKit 基盤は Feature 型を列挙・型消去して payload を解釈せず、owner 単位の admission、管理/復元 hook、再起動照合のための識別子だけを扱う。ActivityKit/WidgetKit は OS 表示と lifecycle の最終決定者である。

| 担当 | 所有するもの |
| --- | --- |
| Feature | `ActivityAttributes` / `ContentState`、`ActivityConfiguration`、開始・更新・最終表示の payload、stale/relevance、Feature local ID、世代、Intent の動詞と業務処理 |
| JibunKit 基盤 | `MiniAppID` による受付閉鎖、owner ごとの登録 hook、管理/復元の順序、保存された binding と OS 列挙結果の照合、購読 Task の寿命、他 owner 保持 |
| OS / ActivityKit | 許可、同時表示上限・更新 budget、Activity ID、表示/終了/破棄、8時間上限、Intent 実行機会。OS が拒否/終了した活動を基盤が成功または存続と見なさない |

推奨境界は Feature-owned の typed actor と、基盤へ渡す owner-scoped closure である。共通 Core に `[String: Any]`、任意 `Codable` payload、timer fields、Feature ごとの attributes switch は置かない。

```swift
// API shape proposal; not compiled on this Windows worker.
public struct MiniAppContinuingSurface: Sendable {
    public let id: MiniAppID
    public let closeAdmission: @Sendable () async throws -> Void
    public let reconcile: @Sendable () async throws -> Void
    public let endOwned: @Sendable (_ reason: EndReason) async throws -> Void
    public let openAdmission: @Sendable () async throws -> Void
}

actor DeliveryLiveActivityService { // Feature module; concrete type stays here
    typealias A = DeliveryAttributes
    func start(localID: String, state: A.ContentState) throws -> Binding
    func update(_ key: ActivityKey, state: A.ContentState) async throws
    func end(_ key: ActivityKey, final: A.ContentState,
             dismissal: ActivityUIDismissalPolicy) async throws
    func reconcile() async throws
}
```

`MiniAppContinuingSurface` は `MiniAppDefinition` の optional registration 候補であり、親が共通契約を固定してから実装する。Feature service の public API は業務型を保つ。基盤 closure の `throws` は ActivityKit の `update` / `end` が throw するという意味ではなく、保存・照合・収束 timeout・受付状態の失敗を運ぶ。

## 確認した native API と最小呼出し

現行 Apple documentation で確認できる signature は次の通りである。

```swift
import ActivityKit

struct DeliveryAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var progress: Double
    }
    let owner: String       // MiniAppID.rawValue
    let localID: String     // Feature-owned stable instance ID
    let generation: UUID    // replacement/restore fence
}

let attributes = DeliveryAttributes(
    owner: owner.rawValue, localID: localID, generation: generation)
let initial = ActivityContent(
    state: DeliveryAttributes.ContentState(phase: "preparing", progress: 0),
    staleDate: nil,
    relevanceScore: 0)

// synchronous and throwing; standard local activity, foreground only
let activity = try Activity<DeliveryAttributes>.request(
    attributes: attributes, content: initial, pushType: nil)

// asynchronous, nonthrowing; ended activity ignores update
await activity.update(ActivityContent(
    state: .init(phase: "moving", progress: 0.5),
    staleDate: .now.addingTimeInterval(15 * 60),
    relevanceScore: 0))

// asynchronous, nonthrowing; include final content
await activity.end(
    ActivityContent(state: .init(phase: "done", progress: 1), staleDate: nil),
    dismissalPolicy: .default)
```

Verified declarations:

- `Activity<Attributes>` is a class constrained by `Attributes: ActivityAttributes`; `ActivityAttributes.ContentState` is Codable/Hashable data. `request(attributes:content:pushType:) throws -> Activity<Attributes>` is synchronous and throws `ActivityAuthorizationError` (including `.denied`). It may start locally only while the app is foreground, except a start performed by `LiveActivityIntent`.
- `update(_:) async` and `end(_:dismissalPolicy:) async` do **not** throw. `update` is ignored after end. State payload for update/final content is limited to 4 KB encoded. The obsolete `contentState:` / `using:` overloads are not proposed.
- `Activity<Attributes>.activities` is a synchronous array of the app's current activities. `activityUpdates` is an `AsyncSequence` yielding activities; each activity has synchronous `activityState` and `activityStateUpdates: AsyncSequence<ActivityState>`. States documented today are `.pending`, `.active`, `.stale`, `.ended`, `.dismissed`.
- `ActivityAuthorizationInfo().areActivitiesEnabled` is synchronous; `activityEnablementUpdates` is asynchronous. This is a preflight/hint, not a substitute for handling a throwing request or later OS termination.
- `ActivityContent.init(state:staleDate:relevanceScore:)` carries Feature state plus OS presentation hints. A stale date changes state to `.stale`; it does not run Feature timers or guarantee an update.
- `ActivityUIDismissalPolicy` offers `.default`, `.immediate`, and `.after(Date)`. Default can retain ended UI on the Lock Screen for up to four hours.
- `ActivityConfiguration<Attributes>` is a WidgetKit `WidgetConfiguration`, `@MainActor @preconcurrency`. It belongs in a widget extension and renders from `ActivityViewContext<Attributes>`; Live Activities do not use widget timelines.
- ActivityKit arrived in iOS 16.1. The current `ActivityContent` overload is the post-iOS-16.1 API family; interactive `Button(intent:)` / `LiveActivityIntent` requires iOS 17-era APIs. This repository already declares iOS 26.0, so no back-deployment branch is needed for the proposed fixture. Exact `@available` declarations must still be compiler-checked against the selected Xcode 26 SDK; no local SDK was available here.

Actor isolation is not stated by the declarations above for `Activity.request/update/end`; do not invent `@MainActor`. The Feature service actor serializes start/update/end and persistence. SwiftUI `ActivityConfiguration` is MainActor-isolated by its documented declaration. App Intent `perform()` is `async throws`; put UI-bound code on `@MainActor` only where the called store actually requires it.

## Identity, persistence, and cold reconnect

Use two related records and never trust either alone:

```swift
struct ActivityKey: Codable, Hashable, Sendable {
    let owner: MiniAppID
    let localID: String
    let generation: UUID
}
struct ActivityBinding: Codable, Sendable {
    let key: ActivityKey
    let systemActivityID: String
}
```

The same three key fields are immutable `DeliveryAttributes`; `Activity.id` is saved only after `request` returns. `systemActivityID` is an opaque lookup aid, not authorization. Every update/end/Intent accepts or reconstructs the complete `ActivityKey`, verifies registered owner, current generation, concrete attributes, and the matching `Activity.id`, then acts. Unknown, foreign, duplicate, or old-generation values are rejected. Never search by `localID` alone.

Start is serialized per owner/local ID. Reconcile before requesting; if the current generation already has an active/stale activity, return its binding rather than duplicate it. If `request` throws, write no binding. If OS start succeeds but binding save fails or the process dies, immutable attributes make the orphan discoverable through `Activity<A>.activities` / `activityUpdates`; report start as incomplete and schedule reconcile, rather than ending another owner or declaring success.

At app cold launch, each registered Feature adapter enumerates only its concrete `Activity<A>.activities`, validates `attributes.owner == registration.id.rawValue`, and joins OS rows with saved bindings by all four identity fields. Rules:

1. matching active/stale row: retain, repair a missing binding, and attach exactly one state subscription;
2. saved row without OS row, or OS `.dismissed`: mark terminal and remove only that binding;
3. OS `.ended`: retain only if the Feature needs final-display bookkeeping; never restart it;
4. OS row with unknown owner, invalid local ID, or non-current generation: do not route it to current business data; end only when the concrete adapter can prove it owns the attributes;
5. duplicate current rows: deterministically retain the saved exact ID if active, otherwise one stable ID, end the other proven-owned rows, and record a diagnostic;
6. B's typed enumeration/storage is never modified while reconciling A.

`activityUpdates` discovers starts made by push/App Intent while the process is alive; `activityStateUpdates` detects stale/end/dismiss. Subscription Tasks belong to the continuing-surface registration, not a screen or `MiniAppRuntime` view task. Reconcile remains required after process death because an AsyncSequence is not a durable log.

## Operation and failure semantics

| Event | Required behavior |
| --- | --- |
| start | check admission and current generation; preflight authorization; call throwing `request`; persist returned ID; attach observation. A denial/limit/invalid content/request failure is visible and does not create a successful binding |
| update | resolve exact key and active/stale activity; cancellation check before deriving state and before call; await nonthrowing `update`; update Feature durable source/binding bookkeeping only in its declared transaction order; observe/reconcile because return is not an OS acknowledgement |
| stop/end | resolve exact key; await `end(finalContent, policy)`; treat `.ended` as non-updatable and `.dismissed` as removed UI. Keep final business data unless Feature explicitly owns deletion |
| cancel user operation | cancellation before request/update/end leaves OS untouched. Once a nontransactional OS call began, cancellation cannot roll it back; finish reconcile and report the observed result |
| permission refusal | `areActivitiesEnabled == false` blocks early; a concurrent change is still handled from `ActivityAuthorizationError.denied`. Existing business data and B remain |
| interruption/process death | cold reconcile recovers OS-start/persist gaps, removes dead bindings, and reattaches streams; never automatically starts a missing activity |
| storage failure | do not overwrite another binding. Start-save failure is an incomplete operation recoverable from attributes; content-save failure must not pretend the durable Feature state changed |
| OS end/limit | state stream/reconcile closes local binding; do not recreate. Apple documents up to eight active hours and up to four more hours on Lock Screen |

Because update/end are nonthrowing, the implementation must not manufacture an `ActivityKitUpdateError`. A bounded `awaitState` helper may produce JibunKit's own `.notObservedBeforeDeadline` and leave a retry/reconcile marker, but cannot claim the OS rejected the call. Multiple simultaneous activities and system limits are OS policy; no fixed numeric concurrency limit should be encoded without device evidence.

## 管理、削除、復元

Proposed connection to existing `MiniAppManagement.Registration`:

- `externalAccess.close` closes shared external mutation, while continuing-surface `closeAdmission` separately prevents new start/update/Intent work. Screen disappearance/background does neither.
- disable/remove order: reserve owner -> close admission -> cancel new-operation tasks -> enumerate/end every **proven-owned** current activity using final content and `.immediate` -> await `.dismissed` or bounded reconcile -> cancel subscriptions/remove bindings -> continue unregister/data deletion. A timeout/storage failure maps to the existing unfinished failure/retry state; management must not show completion first. B stays enabled and untouched.
- retry is idempotent: absent/dismissed activities are already clean; ended rows may be asked to end immediately again; only matching owner rows are considered.
- enable initializes/opens Feature state first, creates a new generation where existing SharedState semantics require it, reconciles, then opens admission. It does not restart prior activities.
- restore `stop` closes admission, fences/cancels Intent work, snapshots diagnostics if needed, and ends current activities before payload replacement. Apply changes SharedState generation. `resume` reconciles and reopens admission but does not re-register an activity. `recoverAfterFailedStop` reopens only if management still permits it. Old Intent/key generations then fail before changing restored data.

This should be a separate optional continuing-surface hook composed alongside `MiniAppSharedState.externalAccess` / `effectiveRestoreLifecycle`; it must not call `MiniAppSharedState.update` from inside another store's coordination closure or promise an atomic transaction spanning ActivityKit and disk.

## Interactive App Intent connection

For a quick action that modifies a Live Activity, define a Feature-owned `LiveActivityIntent`, add it to the **app target**, and use `Button(intent:)` in the Live Activity view. Apple states that this protocol runs in the app process without opening the app. Parameters must already be populated by the view; no interactive parameter resolution is available at tap time.

```swift
import AppIntents

struct AdvanceDeliveryIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Advance delivery"
    @Parameter(title: "Owner") var owner: String
    @Parameter(title: "Local ID") var localID: String
    @Parameter(title: "Generation") var generation: String

    func perform() async throws -> some IntentResult {
        try Task.checkCancellation()
        let key = try ActivityKey.validated(owner, localID, generation)
        try await DeliveryLiveActivityDependencies.service.advance(key)
        return .result()
    }
}

Button(intent: AdvanceDeliveryIntent(
    owner: context.attributes.owner,
    localID: context.attributes.localID,
    generation: context.attributes.generation.uuidString)) {
    Label("Advance", systemImage: "arrow.right")
}
```

The initializer above may need to be explicitly supplied because `@Parameter` synthesis is compiler-sensitive; it is illustrative until Xcode compiles it. The important contract is complete identity, thin intent, cancellation/admission/generation checks, and delegation to the same Feature service. A tap on a locked device requires authentication/unlock according to Apple's widget interaction rules.

P2-W reuse:

- **Reusable:** `MiniAppID`, App Group resolution, `MiniAppSharedState` generation fence/admission, Feature-owned `AppIntentsPackage` registration pattern, entity/parameter identity discipline, management/restore sequencing, cancellation-before-commit tests, and A failure/B retention fixtures.
- **Not directly reusable:** P2-W's ordinary `AppIntent` executes by default in the widget extension, whereas `LiveActivityIntent` executes in the app process and must be in the app target; widget/control timeline reload APIs are not Live Activity updates; a selected `AppEntity` ID is not an ActivityKit ID; UI screen task lifetime is not activity observation lifetime. The existing InteractiveWidgets fixture can inspire two-owner assertions but is not evidence that ActivityKit works.
- An action that only opens detail should remain `widgetURL`/`Link` and existing scene routing. Do not use a no-op `LiveActivityIntent` merely to navigate.

## Project metadata, entitlement, SDK, and signing

Minimum standard local-only setup:

1. App target and embedded widget extension, both compiled with ActivityKit/WidgetKit/SwiftUI types. Add `ActivityConfiguration<FeatureAttributes>` to the extension's `WidgetBundle`; add the Feature package/product to both targets where their types are decoded.
2. App Info.plist `NSSupportsLiveActivities = YES`. `NSSupportsLiveActivitiesFrequentUpdates = YES` is optional and only for frequent ActivityKit **push** updates; users may disable that separately.
3. App and extension must use consistent bundle embedding/signing. For this repository's SharedState reuse, both need the same App Group capability/`com.apple.security.application-groups` entitlement and matching provisioning support. The App Group is required by the selected shared-store design, not by every local ActivityKit app.
4. Local `pushType: nil` does not require APNs. Remote token/push-to-start work additionally requires Push Notifications/APNs configuration, `aps-environment` from the signing profile, a server, and the documented `<bundleID>.push-type.liveactivity` APNs topic. Broadcast channels have additional developer portal capability and are out of the first implementation.
5. No standard Apple source reviewed here documents a separate entitlement or a paid-account gate for local `pushType: nil` Live Activities. Do not assert either. Distribution, App Groups, and APNs have their own signing/profile requirements; measure the actual failing boundary.
6. Repository package deployment is iOS 26.0 and CI uses Xcode 26.x, comfortably above ActivityKit/interactivity introduction. Compile the exact source against the pinned Xcode SDK and inspect the built app/extension plists, entitlements, embedded provisioning profiles, App Intents metadata, and signatures. Windows syntax review is not a substitute.

## Minimal independent A/B fixture and evidence

Use the same source and signing identity in three variants: Standalone A, Standalone B, Combined A+B. Each Feature has a distinct attributes type/owner and deliberately the same `localID`; Combined embeds one widget extension bundle registering both configurations. First use local `pushType: nil` to isolate ActivityKit from APNs.

CI/native build acceptance (one integrated run after parent freezes the contract):

- Xcode compile catches `throws`/`async`/actor isolation/availability and generated App Intents metadata; unit tests exercise exact-key routing, duplicate start suppression, stale generation, cancellation before calls, persistence injection, A disable/remove/restore with B retention;
- inspect final app `NSSupportsLiveActivities`, extension embedding, bundle IDs, App Group entitlements, code signatures/provisioning, and metadata containing each Feature's `LiveActivityIntent`; compare standalone definitions to Combined;
- native tests may directly call Feature service/Intent to prove routing and durable state, but label them non-OS evidence. Simulated fake activities can test the coordinator, not ActivityKit behavior.

Device/UI acceptance, captured as timestamped logs plus screenshots/screen recording and exported diagnostics:

1. authorization value and request result/error; Lock Screen/Dynamic Island (where supported) showing A and B with recorded owner/local/generation/activity ID;
2. start, update, stale transition, final end/default vs immediate dismissal; app background/foreground, force quit/relaunch, and device restart reconcile without duplicate or resurrection;
3. interactive button invokes the correct `LiveActivityIntent`, changes the same durable Feature state and activity, rejects old generation after restore, handles cancellation/failure, and never changes B;
4. A permission refusal/request failure/save-failure injection, A disable/delete retry, and B continuing visibly and durably;
5. normal host after management/restore retains unrelated Feature data and can start a fresh-generation A only by an explicit user/business request.

If the integrated signed app cannot start while the capability-equivalent standalone does, compare (same device/OS, same Apple team/signing identity/profile mode, same Xcode, local `pushType:nil`) the final plist, app/extension entitlements, provisioning profiles, embed graph, console logs, thrown `ActivityAuthorizationError`, `Activity.activities`, and visible UI. Then swap only host composition. This experiment distinguishes source/embedding/metadata defects from account/signing/OS policy. It does **not** prove a paid membership requirement merely from one provisioning failure.

## Open items before implementation

- Parent must choose the exact optional registration name and its composition point in `MiniAppDefinition`/Management/Restore; this lane has not edited shared files.
- Compile-confirm the illustrative Intent initializer and exact Xcode 26 availability annotations. Current documentation confirms the declarations/behavior, but no SDK interface was available locally.
- Decide whether removal acceptance requires observed `.dismissed` or allows a documented retry marker after a bounded timeout; the contract above recommends no completed UI state before dismissal.
- Decide Feature-specific ordering between durable business-state commit and nontransactional ActivityKit update. The common layer cannot make these atomic.
- Remote push, push-to-start, broadcast channels, scheduled/transient iOS 26 activities, and server token ownership are intentionally outside the first local contract.

## Apple primary sources

- [Activity](https://developer.apple.com/documentation/activitykit/activity), [`request(attributes:content:pushType:)`](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:)), [`update(_:)`](https://developer.apple.com/documentation/activitykit/activity/update(_:)), [`end(_:dismissalPolicy:)`](https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:))
- [`activities`](https://developer.apple.com/documentation/activitykit/activity/activities), [`activityStateUpdates`](https://developer.apple.com/documentation/activitykit/activity/activitystateupdates-swift.property), [ActivityState](https://developer.apple.com/documentation/activitykit/activitystate), [ActivityAuthorizationInfo](https://developer.apple.com/documentation/activitykit/activityauthorizationinfo)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities), [ActivityConfiguration](https://developer.apple.com/documentation/widgetkit/activityconfiguration), [Emoji Rangers sample](https://developer.apple.com/documentation/widgetkit/emoji-rangers-supporting-live-activities-interactivity-and-animations)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent), [linking to app scenes](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
- [`NSSupportsLiveActivities`](https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivities), [ActivityKit push notifications](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [WWDC23: Meet ActivityKit](https://developer.apple.com/videos/play/wwdc2023/10184/), [WWDC23: Update Live Activities with push notifications](https://developer.apple.com/videos/play/wwdc2023/10185/), [WWDC26: Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/)
