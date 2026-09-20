# P2-I Push submission

> Historical note: this records the submitted implementation boundary. APNs remains optional and real registration/delivery is unverified; use [the current contract](P2-identity-push-contract.md), [plan.json](plan.json), and [status](../status.md) for current status.

## Contract delivered

- App-level APNs token is held once by `MiniAppRemotePushCoordinator`; Feature/server identity remains owner-scoped.
- Token replacement fans out only to connected owner generations. Registration failure is distinct from provider/server failure.
- `MiniAppRemotePushService` reserves a private lease synchronously, registers cleanup before activation, and binds every callback task to `MiniAppRuntime`. Closed runtimes cannot leak registrations; stop cancels/joins started handlers; generation- and lease-checked cleanup or unregister cannot remove a replacement service.
- Token/failure callbacks are serialized per Runtime generation. Superseded queued callbacks are rejected, and failure clears success state so the same token bytes can be accepted as recovery.
- `onHostLaunch` synchronously publishes a dormant owner. Matching cold/background delivery starts the same management-gated lifetime; disabled owners reject without Feature delivery and the host has no Feature-specific branch.
- Existing `MiniAppNotificationRoute` keys select exactly one owner for foreground/background payload work. Missing, invalid, stopped, or unregistered owners return `noData` rather than broadcasting.
- `MiniAppRemotePushCompletionAggregator` performs one-shot completion fan-in with `failed > newData > noData` precedence; tickets retain aggregation state even after the host method's local aggregator is released.
- Incoming APNs JSON is converted to a recursive Sendable snapshot preserving nested objects, arrays, null, exact signed/unsigned integers and finite fractional values. Large integers never pass through `Double`; NaN, infinity and unsupported values fail before delivery.
- `Tests/P2Push/P2PushProbe.swift` exposes two ordinary `MiniAppDefinition`s using the same local account identifier but separate server identities, lifetimes and unregister hooks.

## UIApplicationDelegate integration

The exact three callbacks and result mapping are documented in `docs/guides/remote-push.md`: forward `didRegisterForRemoteNotificationsWithDeviceToken`, `didFailToRegisterForRemoteNotificationsWithError`, and `didReceiveRemoteNotification:fetchCompletionHandler:` to `MiniAppRemotePushCoordinator.shared` on `MainActor`. Call `UIApplication.registerForRemoteNotifications()` once at host policy level. The parent owns the host wiring, so `Sources/JibunKit/NotificationAppDelegate.swift`, `Project.swift`, workflow and shared ledgers were not edited.

## Native/extension boundary

Coordinator callback tests are fakes and are not described as APNs success. Actual success requires a signed physical-device build, Push Notifications capability/profile, correct `aps-environment`, an APNs provider credential and environment-matched token. Background delivery also needs the Remote notifications background mode and remains OS-scheduled.

No notification service/content extension is required for ordinary owner routing, actions, presentation or background delivery. The guide gives the concrete opt-in connection for mutable-content transformation (owner-namespaced app-group handoff, no Feature runtime in the extension) and reserves a content extension for custom notification UI. Their separate signing targets are deliberately outside the normal core scope.

## Verification

Source tests cover same-token recovery after failure, slow token ordering, closed-runtime rollback, two services for one owner, stop cancellation/join and stale-result rejection, admitted/disabled cold delivery, nested array/null preservation, explicit malformed-payload failure, owner isolation, and a short-lived exact-once completion aggregator. Native fixture tests cover two real definitions, cold launch hooks, same local account/separate servers, correct-owner delivery, independent lifetime stop, and unregister isolation.

- `swift test --filter MiniAppRemotePushTests`: not run on this Windows worker because no Swift executable/toolchain is installed.
- P2 native fixture tests: not run here; the parent task owns generated iOS host integration and CI.
- Static inspection: completed for owned paths and existing route/lifetime/runtime reuse.

## Commit

Implementation commit SHA: `a1315db4f7e9e16a67581b316c7d98f7e0c1124f`

Race-hardening implementation SHA: `e6d53fb3a6b9ac93464be6f92860063b2e98c4d8`

Exact-number snapshot implementation SHA: `79ce409cbaf9d4d89eb6a57c466d2e77a3a4e00b`
