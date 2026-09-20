# Live Activities integration

Development status: targeted for 0.8.2; native build, metadata, and fixture tests
passed. Grouped physical checks covered OS actions, management/restore, restart and normal-app return. One Live B score discrepancy (expected230, observed200 before IPA overwrite) remains unexplained; restarting and Alarm A management/restore after setting210 did not reproduce it. The adopted P2-5 scope is complete based on device evidence and the real four-Feature state/generation regression (31478f2, CI35075825942). The historical observation is not a proven fix. See [source-specific evidence](../verification/2026-09-16-p2-continuing-surfaces-device.md).

JibunKit keeps ActivityKit payloads in the Feature module. Define a concrete
`MiniAppLiveActivityAttributes` type, its business-specific `ContentState`, an
`ActivityConfiguration`, and any `LiveActivityIntent` beside the Feature. Do not
turn delivery state, a match score, or another domain model into a common timer
or untyped payload.

## Coordinator contract

Create one `MiniAppLiveActivityCoordinator<ActivityKitLiveActivityDriver<A>>`
singleton per owner in the **app process**. The Feature supplies:

- its `MiniAppID`, concrete attributes/content types, and current-generation
  admission closure;
- `MiniAppContinuingJournal.shared(owner:namespace:)` for OS bindings outside
  backup business data;
- final Feature content used by management cleanup.

`start` returns a `MiniAppLiveActivityDescriptor`. Keep its complete
identity (`owner`, `localID`, `generation`, `registrationID`) and opaque Activity
ID together. `update`, `end`, and Intent delivery reject a stale generation,
replacement registration, wrong owner, or mismatched Activity ID. Two Features
may deliberately use the same `localID`; owner remains part of the key.

The start input contains the Feature's complete attributes and `ActivityContent`,
so immutable domain attributes, stale date, and relevance score are preserved.
The end input likewise preserves optional final content and `.default`,
`.immediate`, or `.after(Date)` dismissal policy.

The coordinator records `.starting` before `Activity.request`. A request error or
post-request journal failure is not success. Cold `reconcile` repairs an exact
identity match and reports unknown, duplicate, and mismatched OS IDs. Starting
again compares owner/localID/generation, not a newly generated registration ID,
and returns only an OS registration that is still pending/active/stale.

For an update, pass a synchronous `prepare` closure. The gate validates durable
admission, full identity, exact system ID, active journal phase, and current OS
record before invoking this closure. Put the Feature business commit and creation
of the next `ActivityContent` inside it. ActivityKit's nonthrowing `update` return
means “request completed”, not proof that the new content is visible; UI evidence
is separate. An already committed business change followed by OS nonreflection
is an explicit non-atomic partial result. Reconcile checks OS bindings; it does
not retransmit business content. The Feature can explicitly retry its update.

## Host lifecycle

Expose `coordinator.surface(id:finalInput:)` from the Feature singleton. A real
synchronous `@MainActor makeDefinition() throws` must register it together with
backup, removal, durable external access, and the diagnostic View. The fixture
provides `FeatureALiveIntegration.makeDefinition()` and
`FeatureBLiveIntegration.makeDefinition()`. The ordering is:

1. launch/resume: `reconcile`, recover a handle with `current(localID:generation:)`,
   and start passive `observe`; do not reopen a management-closed gate or recreate
   a missing activity. Explicit management enable/resume controls `open`;
2. disable/delete: `close` (drains admitted work), `endOwned`, then ordinary
   unregister/removal;
3. restore stop: `close`, `endOwned`, replace business payload; resume reconciles
   and opens without restarting old work;
4. failed-stop recovery opens only when management still permits the owner.

Cleanup deliberately uses the journal and typed ActivityKit enumeration, not
`MiniAppSharedState.read`, because normal state access is closed during
maintenance. It ends only activities whose immutable attributes prove the same
owner. Unknown typed OS rows stay diagnostic during reconcile and are never
assigned to another owner.

The A and B packages use separate journal namespaces, surface IDs, attributes,
and process singletons while deliberately sharing `same-id`. This also permits a
single owner to add another native type without one adapter deleting the other's
journal. Resetting A does not modify B.

## Targets and metadata

The app and embedded widget extension both depend on the Feature package. Register
each Feature's `ActivityConfiguration` in the extension `WidgetBundle`, and its
`AppIntentsPackage` in targets where metadata discovery requires it. Put
`LiveActivityIntent` in the app-linked Feature product: the system runs it in the
app process without opening the UI, so it must reach the same singleton.

Set the app Info.plist Boolean `NSSupportsLiveActivities` to `YES`. The provided
local adapter uses `pushType: nil`; it does not implement APNs. JibunKit's journal
and shared business store require the same App Group entitlement/container in the
app and extension. Inspect the final built plist, extension embedding, entitlements,
provisioning, signatures, and App Intents metadata rather than inferring them from
source settings.

## Fixture and verification

`Tests/ContinuingLiveActivities/Project.swift.fixture` builds Standalone A,
Standalone B, and Combined from the same two package sources. Each diagnostic
view displays initial state and the latest start/update/end failure. The widget
extension supplies the Lock Screen/Dynamic Island display and interactive button.

Foundation fake tests verify business-key duplicate suppression, pre-mutation
routing rejection, reconcile diagnostics/ending preservation, and cleanup that
continues after one native failure. Native fixture tests pass forged owner,
localID, generation, registrationID, and system ID into the real service and
assert the business value is unchanged. They do not prove ActivityKit behavior. Xcode
and device verification must additionally cover request authorization/error,
Lock Screen/Dynamic Island rendering, Intent metadata and routing, force-quit and
cold reconcile, immediate/default end behavior, disable/delete/restore retry, and
B remaining visible and durable after A fails or resets.

## Apple references

- [Activity and its request/update/end/state APIs](https://developer.apple.com/documentation/activitykit/activity)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [ActivityConfiguration](https://developer.apple.com/documentation/widgetkit/activityconfiguration)
- [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
- [NSSupportsLiveActivities](https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivities)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Emoji Rangers sample](https://developer.apple.com/documentation/widgetkit/emoji-rangers-supporting-live-activities-interactivity-and-animations)
