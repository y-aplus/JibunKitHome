# Sharing the background-refresh slot across features

Status: implementation and macOS/iOS integration tests passed in [run 34683036628](verification/2026-09-12-shared-refresh.md) and shipped in 0.6.0. Real OS acceptance, launch, and expiration delivery were not verified; this is not evidence that the entire background-task scope is complete. The post-release diagnostic fixture was compile-checked only; see [current status](status.md).

## Why a shared path is required

Two standalone apps each have a refresh request slot, but integrated features share one host slot. `MiniAppBackgroundTaskCenter` isolates registration, cancellation, and execution lifetime by native identifier but submits each request directly and does not arbitrate refreshes from several features. Features that share the native refresh slot must explicitly use `MiniAppSharedRefreshCenter`.

Apple documents a pending limit of one app-refresh request and ten processing requests in [`submit`](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submit(_:)); submitting the same pending request replaces it. [`earliestBeginDate`](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate) is a lower bound, not a deadline or exact schedule. The shared center prevents logical requests from overwriting each other; it cannot add OS capacity or execution time. Processing tasks with different network/power conditions are not collapsed into the refresh slot.

## Contract

- At host launch, register one permitted native refresh identifier. Features register handlers under stable owner/local IDs; never make native registration depend on a view.
- One owner may use several local IDs. Only resubmission of the same owner/local ID replaces that logical pending request.
- Persist logical requests in a host-owned journal and submit the earliest lower-bound date to the native scheduler. Do not acknowledge before journal persistence. Because journal and OS submission are not atomic, return “logical request persisted” separately from “OS accepted.” Preserve rejected requests for startup or explicit reconciliation.
- On startup, read the journal, register all available owner handlers, then call `reconcile()`. A corrupt journal is an error, not an empty store. Keep unresolved requests for unregistered owners and never deliver them to another owner.
- On OS launch, freeze generations whose lower bound has arrived; keep future requests pending. A newer generation submitted during execution is not removed by completion/cancellation of the older one.
- Give every due logical request an independent asynchronous execution. The host batch alone owns native completion and calls it once after every execution and cleanup completes.
- Deliver expiration once to unfinished executions in that batch. Expiration notification is not completion; retain an execution after handler removal until it completes. Duplicate or reentrant completion must not finish a later batch.
- Cancelling pending work removes only that owner/local ID and resubmits the native lower bound for what remains. It does not complete in-flight work or cancel unrelated native identifiers.
- Persist an in-flight generation before delivery. If a process exits without a durable acknowledgement, that generation is recoverable and may be redelivered. Feature work must be idempotent for the request generation; exactly-once execution across process death is not promised.

If another direct refresh request already consumes the native slot, preserve it and report native rejection. The host must opt each feature into the shared route; JibunKit does not intercept arbitrary `BGTaskScheduler` calls.

## Host and feature integration

Create one `MiniAppSharedRefreshCenter` with the permitted native ID and a dedicated journal URL, and retain it for the application process. Configure `BGTaskSchedulerPermittedIdentifiers`, background fetch, signing, and launch registration exactly as required by BackgroundTasks.

For each feature, obtain `refreshes(for: context)` and call `register(identifier:handler:)` with a stable local ID. After every feature registration, the host calls `reconcile()`. Do not wait for the feature screen or first submit before native registration.

`submit(identifier:earliestBeginDate:)` throws without acknowledging when persistence fails. After persistence it returns a generation plus native-submission result. `rejected` means the logical request remains stored but the OS did not accept it; call `reconcile()` later. The result includes unresolved requests for unregistered owners. When replacing a handler, register the replacement before host reconciliation.

A handler receives `MiniAppSharedRefreshExecution`. Register cleanup with `onExpiration`, perform cooperative asynchronous work, then call `complete(success:)`. If expiration occurred before the expiration handler was installed, `isExpired` is retained and the handler is notified once after installation. Failure returns the same generation to retryable state; cancel pending work explicitly to stop retrying.

When business work succeeds but durable acknowledgement fails, return `acknowledgementFailed` and mark the native batch failed. Redelivery remains possible, so commit feature updates idempotently with the generation.

One center in one host process owns the journal. Do not point multiple centers or another process at the same file. Validate JSON schema, duplicate generations, and duplicate pending keys. Treat only a missing file as empty. Writes validate and encode before atomic replacement, but do not provide a cross-process transaction or atomic commit with OS submission.

## Required verification sequence

1. With a capacity-one scheduler, accept A and B while retaining one native and two logical requests. Cover date inversion, same local ID under different owners, A-only cancellation, and reconciliation after native rejection.
2. Reopen the journal in a new center and preserve owners, dates, and generations. Corruption, save failure, unregistered owners, and exit between persistence and submission must not erase work.
3. Deliver due A/B while keeping future C pending. A completion must not end B; complete the native task once after all executions. Combine expiration, duplicate completion, handler removal, reentrant launch, and same-ID resubmission during execution.
4. Recover an in-flight journal in a new-process equivalent and make only unacknowledged generations redeliverable. Keep completed and newly submitted generations distinct.
5. On iOS, verify durable journal reload and two-feature handler delivery separately from injected launch. Compare the real native single slot and preservation after one-owner cancellation. Record real OS launch/expiration separately, and never convert a Simulator rejection into wrapper success.

Persistence, batch lifetime, and native integration are one end-to-end feature, not three independently complete claims. Do not replace OS-denied execution with a timer or private API.

## Evidence and remaining limits

Foundation integration tests cover a capacity-one scheduler, save failure, two-feature cleanup, expiration, deregistration, reentrant launch, a new in-flight generation, unknown owners, and real-file reload. The same XCTest runs in the BackgroundTasks fixture. `backgroundtasks_compile_only` limits native-scheduler comparison to build, while injected iOS unit tests still execute.

CI passed the shared suite and 16 new iOS tests plus normal IPA/Search regression. Windows did not execute Swift/Xcode. Injected-scheduler success is not evidence of real OS pending acceptance, launch, or expiration delivery; the real-device single-slot comparison remains outstanding.
