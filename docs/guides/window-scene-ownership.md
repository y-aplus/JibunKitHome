# Window scene ownership

## Ownership model

The host creates one `MiniAppWindowSceneRegistry` for the process and one connection for each actual `WindowGroup` scene. `MiniAppWindowSessionID` is the stable `UISceneSession.persistentIdentifier`; `MiniAppWindowConnection.generation` identifies only the current connection. Reconnecting a restored session retains the former session ID but invalidates its old generation, route callbacks, and scene-scoped resources.

Each window root continues to own its `AppNavigation`, `@SceneStorage`, search state, and presentation state. The registry stores none of those values and does not require Feature navigation values or arbitrary views to conform to `Codable`. A Feature-global `MiniAppRuntime` is also not owned by the scene registry: closing one window must not stop the same Feature in another window.

The development host after 0.8.4 saves the selected Feature ID per scene. Restoration enters the normal navigation admission path; an unavailable or disabled saved owner is cleared so that later reintroduction does not reopen it unexpectedly. This change is not yet in the public 0.8.4 IPA. Arbitrary Feature navigation paths are not automatically serialized.

Use `onDisconnect(owner:connection:_:)` only for resources tied to that window (for example a scene observer or presenter). Explicit disconnect and replacement publish their state transition before awaiting captured cleanup, and `waitForPendingCleanup(in:)` joins cleanup already reserved for that session. An older connect/disconnect can therefore never overwrite a generation installed while cleanup is suspended.

Feature disable/removal/restore calls `await registry.suspendAndRelease(owner:)` first. This closes new scene-resource admission for that owner across every window, detaches all its existing scene resources atomically, and joins their cleanup. The existing management layer then stops/joins its global `MiniAppFeatureLifetime` and performs deletion or restore. Enable/restart completes before `registry.resume(owner:)`. Neither scene cleanup nor suspension shuts down a global runtime automatically; other owners and other windows remain connected.

## Host connection

The host wires the following into `Sources/JibunKit`, `Project.swift`, and the diagnostic workflow. CI and physical results remain separate from this source-level connection description:

1. Enable multiple scenes with `UIApplicationSupportsMultipleScenes = true` in the application scene manifest. Keep the normal `WindowGroup`; do not add a second navigation singleton.
2. Create exactly one process-shared `@MainActor let windowScenes = MiniAppWindowSceneRegistry()` beside the existing shared `MiniAppSceneRouter`. After `MiniAppRegistry.makeManagement`, pass all persisted disabled owner IDs once to synchronous `bootstrapSuspendedOwners(_:)`, before a scene connects. This setup is outside the management provider's Sendable/nonactor `prepare` closure, so that closure does not synchronously cross into `MainActor`. Inject the same registry into every `MiniAppSceneRoot`; never instantiate a registry in a root.
3. Add a host `@MainActor MiniAppWindowConnectionBridge` owned by each root. Its `connect(scene:navigation:phase:selectedID:)` starts a generation-checked MainActor task which obtains `MiniAppWindowSessionID(windowScene.session.persistentIdentifier)`, calls `await windowScenes.connect(...)`, weakly captures the existing `AppNavigation` in the route closure, and stores the returned `MiniAppWindowConnection`. Its `update(phase:selectedID:)` calls `windowScenes.update(storedConnection,...)`. Its `disconnect()` clears its local token and invalidates pending work synchronously, then a MainActor task awaits `windowScenes.disconnect(token)`.
4. Extend the host-owned `MiniAppSceneConnection` with an optional callback carrying the actual `UIWindowScene`. Call bridge connect from that callback. Forward root `scenePhase` and selected Feature changes through the bridge. Call bridge disconnect only from genuine `sceneDidDisconnect`, not SwiftUI `onDisappear` during full-screen presentation. Cancel or generation-check any outstanding bridge connect task when UIKit supplies a newer scene connection.
5. For an event already associated with a scene, call `open(_:in:expected:)` with both its stable session ID and captured connection. Treat `staleConnection` as a dropped late callback. Keep `MiniAppSceneRouter` for process-level notifications that have no target session.
6. Inject `.environment(\.miniAppWindowRegistry, windowScenes)` and `.environment(\.miniAppWindowConnection, bridge.connection)` at the root so Feature packages can register scene resources and explicitly target their own connection without importing the host. Both values are optional for previews and hosts that do not connect this facility.
7. In the parent-owned external-access wrapper for management disable/remove/restore, await `suspendAndRelease(owner:)` before the existing lifetime stop/join. This also joins cleanup already detached by an in-progress connect/disconnect. Keep the owner suspended through mutation; call `resume(owner:)` only after successful enable/restart. `resume` returns `false` while owner cleanup is pending and must not be treated as success. Do not suspend other owners.
8. Use `MiniAppUIKitWindowSceneRequester.requestWindow` for “New Window” and `destroyWindow` for an explicit close command. A successful request call is only acceptance by UIKit; count actual connected `UIWindowScene` sessions before claiming success.
9. Include `Tests/P2Scenes/P2ScenesProbe.swift` and `P2ScenesNativeTests.swift` in the parent-owned diagnostic target. Add both probe definitions to the normal registry so they traverse normal selection, lifetime, and navigation code. The native requester test proves OS creation/destruction only; the parent host bridge test must prove actual host registry delivery.

## iPad verification

On an iPad Simulator and separately on an iPad device when available:

- Run the native test on the required iPad destination. It requests a new session itself, fails rather than skips on rejection/timeout, verifies a distinct connected `UISceneSession.persistentIdentifier`, requests destruction, and observes actual removal. The separate parent host test verifies routing into each actual window root.
- Select A in window 1 and B in window 2, increment each counter to different values, navigate each to a different destination, then target each session explicitly. Verify neither window changes the other's selection, route, or counter.
- Close window 1. Verify its scene resources release while window 2 retains its counter, route, selected Feature, and global Feature work.
- Reopen/restore window 1. Verify its stable session identity where iPadOS restores the same session, a new connection generation, and rejection of a callback carrying the old generation. Verify any `@SceneStorage` value only by observing it after that real reconnect; declaring the property is not evidence.
- After process termination, inspect retained `UIApplication.openSessions` separately from connected scenes. UIKit can retain an archived session without connecting its window at launch. Reactivate that existing session before checking restored UI; creating a new session is not restoration evidence. See Apple's [openSessions contract](https://developer.apple.com/documentation/uikit/uiapplication/opensessions).
- Record request errors, actual session connect/disconnect callbacks, and session IDs. Do not describe adapter compilation, fake callbacks, or a skipped one-window run as an OS multiwindow pass.

Simulator and device results must be reported separately. OS termination may discard in-memory navigation; only explicitly `@SceneStorage`-backed values are expected to restore, and arbitrary Feature view serialization is outside this contract.

## Evidence after 0.8.4

Source `7e4c740` / CI35325946663 exercised actual multiple UIWindowScene sessions in the iPad Simulator, alongside shared routing/lifecycle tests. Physical iPad checks were not performed: the user elected not to prepare a sideload environment. Actual creation/destruction and addressed per-window routing are Simulator evidence, not physical-device evidence. Registry generation/restoration tests do not yet establish real OS cold session restoration: a two-window terminate/relaunch UI test is being added for that boundary. Merely declaring SceneStorage does not prove OS session restoration.

Source `1138ded` / CI35352655988 passed the real OS regression that restores a selected owner, omits it at a later launch, and verifies that reintroducing it does not revive the cleared selection. Its two-window test passed creation and independent state setup, then failed an incorrect assumption that both retained sessions would connect immediately after relaunch. The corrected test at `99632e3` / CI35355170934 passed: both original session IDs remained archived, activation restored both owners and distinct values, and closing A preserved B. Native82 and OS UI5 passed with no failures/skips on iPad (A16), iOS26.5 Simulator. Physical iPad remains untested.
