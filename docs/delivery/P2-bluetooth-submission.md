# P2 Bluetooth submission

> Historical note: this submission records the delivered change at that point in time. It is not the current completion ledger; use [plan.json](plan.json), [status](../status.md), and the current Bluetooth guide.

## Delivered boundary

- `MiniAppBluetoothCoordinator` and `MiniAppBluetoothService`: tokenized owner admission, scan/connect/disconnect, service/characteristic discovery, backpressured read/write/subscribe, generation filtering, joined shutdown, lease-safe unregister, and cold restoration handoff into the same lifetime.
- `MiniAppCoreBluetoothCentral`: normal CoreBluetooth central adapter with owner-specific restoration identifiers and retained peripheral/service/characteristic delegates.
- Pure XCTest coverage for two-owner isolation, owner-stop and same-peripheral transition barriers, runtime-registration rollback, stale/duplicate callbacks, power/authorization gates, disabled restoration, and write backpressure.
- `P2BluetoothProbe`: two ordinary Feature definitions using independent, explicitly initialized `MiniAppFeatureLifetime` instances. Native fixture lifecycle/management tests inject fake centrals and never instantiate `CBCentralManager`; the real adapter is compile-only until an explicit device run.

## Host integration

The parent-owned host should append `P2BluetoothProbe.definitions` to its registry/native fixture, call existing `onHostLaunch` hooks after persisted management admission is applied, and compose `UIBackgroundModes = [bluetooth-central]` plus a Bluetooth usage description into the fixture manifest. No host, manifest, project, or workflow file is changed by this submission.

Shutdown order is management/consent admission close, callback delivery close, native cancellation request and completion join, then unregister/removal. Normal late callbacks can never create ownership; only an explicitly opened restoration window can adopt a restored generation. A disabled or denied owner's launch hook passes `false`, so no `CBCentralManager` exists to restore it.

## Evidence and remaining checks

The pure tests use an instrumented fake and must not be described as radio evidence. An iOS Simulator native build proves adapter compilation only; Simulator lacks the BLE radio behavior needed for this contract. Real-device radio, permission UI, background wake, termination/relaunch restoration, and reboot remain manual device checks described in the guide. Real APNs/CloudKit and P2 background/cold/radio validation remain outside this submission.

This worker ran on Windows where `swift`/`swiftc` is not installed. Therefore neither SwiftPM XCTest nor the iOS/CoreBluetooth compile was run here; the parent native boundary must run both against this exact source commit on macOS/Xcode 26.

Swift 6 review: coordinator, service, adapter, delegates, and XCTest fixtures are `@MainActor`; escaping event callbacks are explicitly main-actor/sendable and capture owners/services weakly where lifetimes can outlive consumers. Runtime cleanup captures stable owner/token values and clears only the matching service generation.
