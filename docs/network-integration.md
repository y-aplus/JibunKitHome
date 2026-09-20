# Network store integration

## Ephemeral session and cache isolation

For networking that does not require a persistent login, combine Foundation's private in-memory cookie/credential stores with a feature/profile-specific `URLCache`:

```swift
let configuration = URLSessionConfiguration.ephemeral
configuration.urlCache = try context.urlCache(
    memoryCapacity: 4 * 1024 * 1024,
    diskCapacity: 32 * 1024 * 1024,
    containerURL: container,
    profile: "account-1"
)
let session = URLSession(configuration: configuration)
```

The feature chooses capacity and owns the session/cache for its useful lifetime; do not reconstruct them for every request. If several sessions in one profile intentionally share state, pass the same stores explicitly. Never pass them to another feature. Changing the source configuration after session construction does not reconfigure that session.

`URLSession.shared` and a default configuration retain shared cookie/credential behavior. The example permits a disk cache but does not persist cookies or credentials. `URLCache` remains evictable and is not a durability promise across process recreation, IPA updates, or signing changes. Persistent-login products may choose an explicit persistent adapter instead of being forced to ephemeral storage.

## Runtime shutdown and restore

Register networking tasks with the feature runtime and wait for actual completion after cancellation. The feature owner connects session invalidation, delegate cleanup, login-store updates, and restore behavior. Calling `invalidateAndCancel()` is not proof that every callback has finished. Use `MiniAppURLSessionLifetime` when native invalidation completion is required, and connect it to `onShutdownAsync`; see [runtime and restore integration](runtime-restore-integration.md).

Background-session reconnection has a separate [integration contract](guides/background-urlsession-reconnect.md). An App Group cookie store is shared according to signed group membership, not automatically isolated by an arbitrary feature name.

## Explicit persistent cookies

Construct one live owner per feature/profile before creating the session:

```swift
let cookies = try MiniAppCookieStore(context: context, profile: "account-1")
let configuration = URLSessionConfiguration.ephemeral
configuration.httpCookieStorage = cookies.storage
```

After a login response or other state change completes, call `try cookies.save()` and treat persistence as successful only after it returns. Multiple owners saving the same profile can overwrite newer state. Shutdown order is close request admission, wait for all requests, then save. Do not `reload` while a response may be mutating the store.

For local logout, stop requests and call `try cookies.clear()`. For server logout, await the response and save the resulting store. Never report success when Keychain deletion fails. Session-only and expired cookies are not restored; absolute expiry prevents a relative Max-Age from being extended at every restart.

Saving is explicit, not automatic. Forced termination before save, concurrent owners, and another-process writers remain outside the guarantee. Validate the whole archive before replacing either persistent or live state. Reject corrupt/unsupported versions and cookies whose reconstructable expiry, name, value, domain, path, Secure, HttpOnly, version, or port changes; preserve the old snapshot on failure. This is not a claim of complete support for every attribute such as SameSite.

A profile is a stable account identifier. Switching the profile string on an existing owner does not retarget an already-created session; construct a new store/session pair and retain the old owner until its requests finish. Profiles such as `/../` or non-ASCII strings remain distinct Keychain accounts rather than filesystem paths.

## Explicit HTTP password credentials

`MiniAppPasswordCredentialStore` joins a feature/profile-specific `URLCredentialStorage` with a Keychain snapshot and is independent of cookies:

```swift
let passwords = try MiniAppPasswordCredentialStore(context: context, profile: "account-1")
let configuration = URLSessionConfiguration.ephemeral
configuration.urlCredentialStorage = passwords.storage
// Attach cookies.storage and context.urlCache here too when needed.
let session = URLSession(configuration: configuration)

let credential = URLCredential(
    user: username,
    password: password,
    persistence: .forSession
)
passwords.storage.setDefaultCredential(credential, for: protectionSpace)
try passwords.save()
```

`save()` explicitly persists every password credential currently in this private store. `.forSession` describes native store lifetime and does not suppress explicit save. For “do not remember,” omit save or use a distinct nonpersistent store/session. Restoration recreates `.forSession` credentials and never substitutes Foundation's shared permanent/synchronizable Keychain storage.

The snapshot preserves host, port, protocol, realm, authentication method, proxy distinction, multiple users, and the default user for each standard `URLProtectionSpace`. Assign the store before session creation. A custom authentication delegate must explicitly use this feature store and must not fall back to the shared one.

Logout order is stop new requests, finish the session, then `try passwords.clear()`. Store deletion does not invalidate authenticated connections or credentials retained by a delegate, so subsequent work starts with a new session. Preserve and report save/clear errors. Validate all records, duplicates, default-user existence, and native protection-space reconstruction before replacing the live store; one profile has one live owner.

This adapter does not cover client-certificate identities, server trust, SSO, biometric access, synchronized Keychain, or actual Digest/proxy-auth communication. Use the separate [Keychain access-control](guides/keychain-access-control.md), [web-authentication](guides/web-authentication-ownership.md), and background-reconnection contracts when applicable.

## Wait for request and delegate completion

Forward native invalidation after any feature-specific asynchronous delegate cleanup:

```swift
final class FeatureSessionDelegate: NSObject, URLSessionDelegate, Sendable {
    let lifetime = MiniAppURLSessionLifetime()

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task {
            // Finish feature-specific asynchronous cleanup first.
            await lifetime.didBecomeInvalid(session, error: error)
        }
    }
}

let delegate = FeatureSessionDelegate()
let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
// Close feature admission and cancel/join owned runtime tasks when required.
try await delegate.lifetime.finishAndWait(session)
try cookies.save() // Or clear for logout; handle the password store as needed.
```

One lifetime belongs to one session. Reuse with another session or an unfinishable shared session is an error. Concurrent finish calls join one result, and an invalidation notification that arrived early is retained. Cancelling a waiting task never reports cleanup early. A finished session is not reused.

Internally, `finishTasksAndInvalidate()` is called once and the lifetime awaits delegate invalidation after existing requests/callbacks finish. To cancel work, first cancel and join runtime-owned tasks, then enter this wait. Do not synchronously await it from a callback that it is itself waiting to finish. A missing delegate forward or unfinished feature cleanup intentionally leaves the wait incomplete.

`onShutdownAsync` cannot throw, so retain any save/clear error in feature state and inspect/report it after `runtime.shutdown()`; do not hide it as success. This lifetime does not cover another process or background-session event reconnection.

## Evidence and limits

[`MiniAppHTTPIsolationTests`](../Tests/JibunKitCoreTests/MiniAppHTTPIsolationTests.swift) exercise real loopback HTTP cookie delivery, cache-only reads, redirects, authentication challenges, and isolation. Runs 34433288351, 34435476250, and 34437448875 cover cookie/credential restoration, corrupt archive preservation, multiple profiles/users, process restart, and owner isolation. Run 34439496158 covers slow responses, delegate cleanup, logout ordering, duplicate/early invalidation, and wrong-session rejection. The 0.8.0 host/device results are linked from [feature HTTP integration](guides/feature-http.md) and the [device record](verification/2026-09-14-0.8-device-check.md).

These results do not complete every networking/coexistence scenario, guarantee cache persistence, or prove every authentication method and cookie attribute. Detailed historical runs remain in the [network isolation record](verification/2026-09-10-network-isolation.md).
