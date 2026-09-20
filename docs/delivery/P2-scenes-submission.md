# P2 scene submission

> Historical note: this submission records the delivered scene boundary at that point. Current adopted-scope status and remaining physical iPad conditions are tracked in [plan.json](plan.json) and [status](../status.md).

## Delivered

- A process registry separating stable OS session identity from ephemeral connection generation.
- Exact-session route delivery with stale-generation rejection.
- Reentrancy-safe scene transitions which publish the new generation before awaiting tracked old cleanup, retain owner sets on pending cleanup, and make new connections join prior cleanup for the same session.
- Scene-scoped, owner-grouped cleanup and `suspendAndRelease(owner:)` for management to close admission and join that owner across every scene while preserving other windows/owners and Feature-global runtimes.
- UIKit request adapter for OS window creation/destruction without treating request acceptance as successful window creation.
- Core tests for two-window isolation, close/other-window retention, cleanup order, restoration, late delivery, and stale disconnect.
- Optional SwiftUI environment values exposing the current connection and process-shared registry to Feature packages, plus synchronous bootstrap admission for persisted disabled owners.
- An iOS probe with two normal `MiniAppDefinition` values, per-window `@SceneStorage`, and a native diagnostic that requests, observes, and destroys a second real `UIWindowScene` without manual setup or skip. Actual host delivery remains a parent bridge test, not a claim from an independent registry.

## Parent-owned integration diff

No parent-owned file was edited. The required host/manifest/test-target changes are listed step by step in [window-scene-ownership.md](../guides/window-scene-ownership.md#host-connection). In summary: enable multiple scenes; create one process-shared registry; synchronously bootstrap persisted disabled owners before scene connection; add one root-owned connection bridge using the real `UISceneSession.persistentIdentifier`; expose its registry/token through the Core SwiftUI environment; keep the returned generation; disconnect only on genuine UIScene disconnection; connect management stop/join through `suspendAndRelease(owner:)` and checked `resume(owner:)`; use explicit session delivery when known; add the two probe definitions to the normal registry; and compile the P2Scenes files in the diagnostic target.

The existing `MiniAppSceneRouter` needs no change: it remains the fallback for process events with no OS session target. The new registry handles the distinct explicit-session contract.

## Validation boundary

The core tests are meaningful model/ownership checks but are not proof that iPadOS created two windows. The native test has no skip path: it requires the parent-selected iPad destination, requests a second session, and fails on explicit rejection, connection timeout, destruction rejection, or removal timeout. Simulator and device evidence remain distinct claims.

This worker ran on Windows where `swift` is unavailable, so no Swift build or test is recorded as executed. `git diff --check` and path-boundary inspection were run. The UIKit signatures were checked against Apple documentation for `UISceneSessionActivationRequest`, `activateSceneSession(for:errorHandler:)`, `requestSceneSessionDestruction(_:options:errorHandler:)`, `openSessions`, and `UISceneSession.persistentIdentifier`; compilation remains for the parent Xcode boundary.

Swift 6 review points: public mutable coordinators and callbacks are `@MainActor`; escaping callbacks retain no host navigation in the core; callers are instructed to capture the window root weakly; async cleanup closures execute on `MainActor`; XCTest classes containing async actor-isolated tests opt out of implicit Sendable checking. The UIKit requester and its sendable failure callback are both `MainActor` isolated.

## Not claimed

- No actual iPad Simulator/device two-window operation has been run by this Windows worker.
- OS state restoration beyond values the host explicitly places in `SceneStorage` is not promised.
- Window request acceptance is not counted as creation or destruction.
- Feature disable/removal/restore orchestration remains in the existing global management lifecycle; this registry does not replace it.
