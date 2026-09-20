# Scene and navigation ownership

## Current contract

Each `MiniAppSceneRoot` inside `JibunKitApp`'s `WindowGroup` owns its own `AppNavigation` in `@State`; there is no process-global `NavigationPath`. Search and backup sheets are likewise scene-local view state. A URL received by a scene is routed directly into that scene's navigation.

Process-level notifications do not identify a target scene, so `AppSceneRouting.shared` selects a destination through `MiniAppSceneRouter`; it does not share navigation state. A root registers when attached to its window and updates its active phase. It remains registered while a feature-owned full-screen presentation hides the root. Unregister only on actual `UIScene` disconnection or root destruction, and register again on a later connection. Handlers weakly reference navigation.

The router applies these rules:

- Prefer active registered scenes; among several, choose the most recently transitioned to active. Duplicate active notifications do not reorder them.
- If none is active, use the most recently registered or activated remaining scene. This does not bring the OS window to the foreground.
- If no scene exists, retain the last request and deliver it to the first registration. A `nil` destination is a real request for the feature list.
- Deliver once, never broadcast. A reentrant request is queued and selects again after the current delivery. A removed registration cannot win later selection.
- Notification custom actions and dismissals remain routed to their feature owner and do not enter screen selection.

## Navigation inside one scene

The selected feature view is the `NavigationStack` root and registers its destinations inside that stack. The path contains detail values only; an empty path means the feature root. `MiniAppDefinition.navigationPath(for:)` and `appendDestination` receive an initially empty path, so features do not append their `MiniAppID`.

`AppNavigation` stores a separate value path for every feature in the scene. Switching from the bottom menu returns to the target feature's last value-based path; returning through the feature list also preserves it. Native Back pops normally and does not resurrect popped details. “This app's first screen” clears only the selected feature path.

A destination-free URL/notification explicitly opens the target root rather than resuming its switcher path. A destination-bearing event replaces that feature's path only after integration validation succeeds. Invalid or unsupported destinations preserve the current and stored paths, and never alter another feature. Keep the switcher outside the `NavigationStack` in a reserved safe-area region so it does not depend on feature toolbars or cover content.

Update the stack identity and binding generation when switching. This prevents two features using the same Swift navigation-value type from reusing destination registrations, and prevents a departed stack's late binding write from mutating the new path after returning.

This is in-memory value navigation for `NavigationLink(value:)` and `navigationDestination(for:)`. It does not preserve destination-view links, view-local input, sheets, arbitrary UIKit stacks, or paths across application termination; feature values need only be `Hashable`, not `Codable`.

## Scene lifetime and full-screen presentation

A feature-owned full-screen UI can temporarily remove the presenting view from the hierarchy without disconnecting its `UIScene`. Do not disconnect on `onDisappear` or temporary `view.window == nil`. `MiniAppSceneConnection` closes when its `UIWindowScene` disconnects or the root is destroyed. Background/inactive and actual feature-selection events still flow normally, and camera stop rules are unchanged. This boundary was added after document scanning exposed `unavailable("no active selected scene")`/`stopped` on source 306874f.

SwiftUI [`WindowGroup`](https://developer.apple.com/documentation/swiftui/windowgroup) provides per-window state for state stored in the window hierarchy. [`ScenePhase`](https://developer.apple.com/documentation/swiftui/scenephase) is scene-specific when read in a view, while the app-level value remains aggregated. Root phase drives routing selection and [feature scene activity](guides/scene-feature-activity.md).

## Evidence and remaining limits

[`MiniAppSceneRouterTests`](../Tests/JibunKitCoreTests/MiniAppSceneRouterTests.swift) cover selection, single delivery, phase changes, removal, prelaunch pending state, and reentrancy. CI 34440565104 verified two independent navigation objects and normal notification routing. CI 35102558612 verified UIKit full-screen presentation/re-presentation and disconnect/reconnect behavior. The corrected document-scan flow has not yet been rechecked on a device.

These tests do not operate two real iPadOS windows. Multiple-window manifests, creation/destruction/foreground policy, session-identifier delivery, arbitrary UIKit roots, and persistent full-screen restoration are separate scope. Feature-owned sheet/full-screen/UIKit presentation cleanup shipped in 0.7.0, but it does not preserve arbitrary view `@State`. See [navigation evidence](verification/2026-09-10-feature-navigation.md) and [feature-owned presentations](guides/feature-owned-presentations.md).

Historical CI 34440305199 failed before router/UI tests because a Core-only test referenced `MiniAppID.counter` from CounterFeature. The correction uses explicit IDs and does not add a CounterFeature dependency to Core; 34440565104 is the succeeding run.
