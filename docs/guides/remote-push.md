# Remote Push ownership

`MiniAppRemotePushCoordinator` owns the single app-level APNs device token. A token is not a Feature credential. Each Feature creates a `MiniAppRemotePushService` with its `MiniAppID` and its own `MiniAppRemotePushIdentity(server:account:)`; its registration callback sends that tuple and the current app token to that Feature's server implementation.

Connect the service from `MiniAppFeatureLifetime` configuration:

```swift
let service = MiniAppRemotePushService(
    owner: id,
    identity: try MiniAppRemotePushIdentity(server: "push.example.com", account: accountID),
    onRegistration: updateServerRegistration,
    onDelivery: processFeaturePayload
)
let lifetime = MiniAppFeatureLifetime(id: id) { runtime in
    try service.connect(to: runtime)
}
```

For cold/background delivery, publish the owner synchronously from the ordinary definition's launch hook:

```swift
onHostLaunch: { service.prepareColdStart(lifetime: lifetime) }
```

This does not start the Feature at launch. A matching payload asks the same lifetime to start; persisted management admission (`setStartAllowed(false)`) rejects it without calling Feature business code. The host needs no Feature-specific switch.

Runtime shutdown disconnects only that owner and invalidates its generation. Management deletion should expose `onUnregister: { await service.unregister() }`. Active registration/delivery handlers are Runtime-owned; the service's distinct `onUnregister(identity)` server-cleanup closure is instead awaited by management after Runtime stop. An older service lease cannot remove or unregister its replacement. A token change is serialized per current Runtime generation. APNs registration failure is reported separately and a later success with the same token bytes is still accepted.

Incoming payloads must contain `JibunKitMiniAppID`; optional navigation uses `JibunKitDestination`, matching the existing notification router. `deliver(userInfo:)` resolves exactly one active owner. It never broadcasts an unowned payload. `MiniAppRemotePushMessage.payload` is a recursive, Sendable snapshot that preserves APNs JSON strings, signed/unsigned integers, finite fractional numbers, booleans, arrays, objects and null. Integers such as `Int64.max` are never converted through `Double`; unsupported native objects, non-string keys, NaN and infinity are rejected as `failed` before Feature delivery. Feature-specific schema validation and business work belong in `onDelivery`.

## UIApplicationDelegate connection

The JibunKit host already forwards the three delegate callbacks below. Enable automatic launch-time `registerForRemoteNotifications()` by declaring `JibunKitRemotePushEnabled = true` in the app Info.plist through the existing Feature build requirements. Also supply the valid `aps-environment` entitlement/profile, and `remote-notification` background mode for background delivery. The flag does not supply signing capability. Notification display authorization is a separate decision; denying alerts is not itself a reason to discard background registration.

For another host, the equivalent callback wiring is shown below. Its management and launch-error gates must reject disabled or failed owners before delivery, as `NotificationAppDelegate` does in JibunKit:

```swift
func application(_ application: UIApplication,
  didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    Task { @MainActor in
        MiniAppRemotePushCoordinator.shared
            .didRegisterForRemoteNotifications(deviceToken: token)
    }
}

func application(_ application: UIApplication,
  didFailToRegisterForRemoteNotificationsWithError error: Error) {
    Task { @MainActor in
        MiniAppRemotePushCoordinator.shared
            .didFailToRegisterForRemoteNotifications(error)
    }
}

func application(_ application: UIApplication,
  didReceiveRemoteNotification userInfo: [AnyHashable: Any],
  fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
    Task { @MainActor in
        let value = await MiniAppRemotePushCoordinator.shared.deliver(userInfo: userInfo)
        completion(switch value {
        case .newData: .newData
        case .noData: .noData
        case .failed: .failed
        })
    }
}
```

When the host has other app-level consumers, create a `MiniAppRemotePushCompletionAggregator`, obtain one ticket per consumer, call `finishAdding()`, and map its single aggregate result to `UIBackgroundFetchResult`. Failure wins over new data, which wins over no data; duplicate ticket completion is ignored.

## APNs and extensions

APNs is an optional host capability. Successful build, entitlement composition, or simulated delivery does not prove production APNs communication; the adopting application must verify signing, environment, registration, provider delivery, and real-device behavior. Features that exchange remote data must continue to support the mandatory generic HTTP boundary without requiring APNs.

Real registration requires a signed iOS app with the Push Notifications capability and an APNs entitlement/profile. Background delivery additionally requires the Remote notifications background mode; APNs delivery is opportunistic and is not a durable job queue. Provider authentication, environment-correct device token storage, token replacement, payload signing, retries, and deletion after provider rejection are server responsibilities.

The normal JibunKit flow does not require a notification service or content extension. Add a service extension only when mutable-content media/decryption is an actual product requirement. That separate target receives the app notification before the host, has a short OS deadline, and cannot start a Feature runtime; use an app-group handoff namespaced by `JibunKitMiniAppID`, then let the host route normally. A content extension is needed only for custom notification UI and likewise must not run Feature business processing. Both targets require their own bundle IDs, provisioning and extension entitlements, so they are intentionally not generated by this core API.

Tests that directly invoke coordinator callbacks prove ownership, token-change, failure, generation and completion behavior only. They do not prove APNs registration, provider acceptance, device delivery, background launch, or extension execution.
