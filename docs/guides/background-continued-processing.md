# iOS 26 continued processing

`MiniAppContinuedProcessingCenter` is the host-shared ownership boundary for work that a
person explicitly starts in the foreground and expects to continue after backgrounding the
app. It complements, rather than replaces, the existing APIs:

- use `MiniAppBackgroundTasks` for discretionary refresh and processing scheduled by the OS;
- use `MiniAppSharedRefreshCenter` when Features share the app-wide refresh opportunity;
- use background `URLSession` for OS-owned transfers and reconnect its delegate through
  `MiniAppBackgroundURLSessionReconnectRegistry`;
- use `MiniAppBackgroundExecution` only for short UIKit completion grace time.

Create one center for the host process and give each Feature an owner-limited handle. Put a
wildcard base in `BGTaskSchedulerPermittedIdentifiers`, for example
`com.example.app.export.*`. A foreground user action constructs one request with a unique UUID
suffix; JibunKit registers that fully composed identifier and submits it as one operation:

```swift
let center = MiniAppContinuedProcessingCenter()
let tasks = center.tasks(for: MiniAppContext(id: featureID))
let request = MiniAppContinuedProcessingRequest(
    baseIdentifier: "com.example.app.export",
    title: "Export video",
    subtitle: "Preparing",
    strategy: .queue
)
let receipt = try tasks.submit(request) { execution in
    execution.onExpiration = { cancelAndCheckpointExport() }
    startExport(
        progress: { completed, total in
            execution.reportProgress(completed: completed, total: total)
            execution.updateTitle("Export", subtitle: "\(completed) / \(total)")
        },
        completion: { success in execution.complete(success: success) }
    )
}
```

Submit only as the immediate result of a foreground user action. The request exposes the exact
`identifier` (`baseIdentifier.UUID`) and its matching `permittedIdentifier`
(`baseIdentifier.*`). Never reuse a job UUID in one process. `.queue` asks the system to start as
soon as capacity becomes available; `.fail` reports submission failure when it cannot start
immediately. Continued-processing launch handlers are intentionally registered at this user
intent point; unlike refresh and processing handlers, Apple does not require these handlers to be
registered during app launch.

The Feature still owns the operation, results, checkpoints, and generation checks. An expiration
callback, including cancellation from the system Live Activity, is a cleanup request. Cancel the
work, await or otherwise finish cleanup, then call `complete(success: false)`. Completion is
idempotent, late expiration is not delivered to a completed execution, and the center retains an
execution until completion. `cancelPendingRequest` is owner checked and cancels only that exact
queued identifier; it is not process-wide cancellation and does not silently complete a running
operation. The center closes launch admission before cancelling a pending job and after a
failed submission. Late or duplicate native deliveries are completed unsuccessfully without
calling the Feature again; a new job and other owners remain independent.

The wildcard base, including its literal trailing `.*`, must be present in the composed host
`BGTaskSchedulerPermittedIdentifiers`. The fully composed identifier passed to registration and
submission contains a nonempty unique suffix matching that wildcard. JibunKit records its owner,
rejects duplicate UUIDs, and fails a late native launch if the center has already been released.
Do not request background GPU resources through this wrapper: GPU capability and entitlement are
an optional, separate integration and are outside this boundary.

For re-signing hosts, put the build-time app bundle ID in
`JibunKitOriginalBundleIdentifier` in the app Info.plist. The JibunKit host supplies
`com.jibunkit.app`. The native refresh, processing, shared-refresh, and continued
adapters resolve logical task IDs against the installed `CFBundleIdentifier` and
permitted task list. They replace the original bundle prefix only when the
result is explicitly permitted (including continued-task wildcard entries).
Feature IDs, stored owner IDs, job UUIDs and returned logical receipts remain
unchanged; registration, submission and cancellation use the same native mapping.
Unrelated namespaces and signers that leave the task list unchanged retain their
existing IDs. No suffix-only or cross-owner match is used.

This handles the task-list rewrite present in
[SideStore's re-sign operation](https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/ResignAppOperation.swift).
It does not establish that every signing configuration supports background
execution. A rejected launch registration is reported for that Feature, and its
lifetime rejects starts for the rest of the process. Other Features still
register. Correct the launch conditions and restart; toggling management enable
does not repeat an OS registration that may already have partially succeeded.

The system owns admission and runtime. A successful `submit` does not prove launch, and invoking a
stored launch closure in a test is not OS-launch evidence. The system may terminate work under
resource pressure, cancels queued work when a person closes the app from the app switcher, and may
terminate running work there without delivering an expiration callback. Persist recoverable
Feature state independently of the execution object.

Apple references:

- [Performing long-running tasks on iOS and iPadOS](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados)
- [BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)
- [BGContinuedProcessingTaskRequest](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)
- [`BGContinuedProcessingTaskRequest.init(identifier:title:subtitle:)`](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/init(identifier:title:subtitle:))
- [Finish tasks in the background (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/227/)


## Submission results on iOS 27

For admission diagnostics and complete error reporting, use the additive
`tasks.submitReportingResult(request, completion: ..., launch: ...)` API. It returns
the owner-scoped receipt immediately after registration so pending admission can
be cancelled. Its MainActor completion reports success or error at most once;
launch remains a separate callback. Registration/validation failures still throw.
The existing synchronous `submit` API is retained for source compatibility.

When built with Xcode 27/Swift 6.4 and running on iOS 27, the native adapter uses
`BGTaskScheduler.submitTaskRequest(_:completionHandler:)` off the main thread.
SDK/OS 26 builds fall back to the legacy synchronous submission and cannot promise
the same error coverage. A late successful response after cancellation cancels
that exact request again; it cannot reopen launch admission or cancel other owners.
The diagnostic labels the selected API and keeps request, admission response, and
OS launch separate. It never substitutes foreground work for an OS launch success.

Apple DTS describes missing errors from the old synchronous API in
[the accepted response](https://developer.apple.com/forums/thread/807370).
The [new API documentation](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submittaskrequest(_:completionhandler:))
does not give a bounded response time. Its off-main warning is disputed by
[Apple DTS clarification](https://developer.apple.com/forums/thread/840876), which
states the new API supports any thread, including main. This adapter keeps its
off-main call; that scheduling choice is not evidence of a cause or fix. This
explains why a synchronous success alone is insufficient; it does not establish
the cause of the current physical-device failure.
