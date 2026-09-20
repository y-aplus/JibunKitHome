# P2-4 background delivery proposal

> Historical note: this is the pre-implementation proposal and does not represent current completion status. Use [plan.json](plan.json) and [status](../status.md) for the current adopted scope and remaining observation limits.

Date: 2026-09-17
Baseline: `57542e66981373d2de3d112aca91ea1aa56c07cf`

## Decision and implementation

The existing background components remain the normal implementation:

- `MiniAppBackgroundTaskCenter` already preserves `BGAppRefreshTaskRequest` and
  `BGProcessingTaskRequest`, launch/expiration/completion, exact owner cancellation, and native
  registration rejection.
- `MiniAppSharedRefreshCenter` plus `FileSharedRefreshJournal` already persists pending/running/
  recovery generations, reconnects registered Feature handlers after cold process launch, and
  completes the native batch only after every logical job finishes.
- `MiniAppBackgroundURLSessionReconnectRegistry` already derives stable owner/profile identifiers,
  joins duplicate host callbacks, retains every completion until the Feature delegate reports
  `urlSessionDidFinishEvents`, and protects replacements from stale registration/event tokens.
- `MiniAppBackgroundExecution` remains the short UIKit grace-time API and is not presented as a
  scheduler.

The missing iOS 26 path is implemented as `MiniAppContinuedProcessingCenter`. Each foreground
action supplies a wildcard base and a new UUID. The center dynamically registers and submits the
fully composed `base.UUID` identifier, keeps exact owner/job ownership, forwards `.queue`/`.fail`,
title and subtitle, exposes native progress and title updates, hops expiration to `MainActor`,
retains each launched execution through asynchronous cleanup, and completes the native task exactly
once. Pending cancellation is exact and owner checked. A launch after center release is explicitly
failed instead of abandoned. The wrapper intentionally excludes optional GPU resources and does
not turn user-initiated work into automatic maintenance.

`P2BackgroundProbe.definitions` supplies two real Feature definitions with
`MiniAppFeatureLifetime`, `onUnregister`, and restore lifecycle. Each launch hook registers an
ordinary refresh/processing identifier, one owner in the durable shared-refresh journal, and a
background URLSession reconnect factory. Continued registration occurs later at the explicit user
action, as required by this API. Runtime shutdown first closes admission, cancels the exact pending
job, cancels and awaits the worker, and then idempotently completes the native task. A late launch
is failed. Restore starts a new Feature generation but never restarts business work.

The diagnostic UI can submit ordinary refresh/processing and shared refresh, inspect pending or
recovery journal generations, and start a real background `URLSessionDownloadTask` from an input
URL. Downloads use stable owner/profile session identifiers and move results into owner-specific
Application Support directories. The UI reports delegate completion counts and distinguishes
transfer completion from `urlSessionDidFinishEvents`/host-completion release. The continued job
runs for about 60 seconds so progress and system cancellation are observable; tests replace only
that work loop with a deterministic gate.

The follow-up management correction applies the same admission rule to every background entrance,
not only continued processing. Ordinary and shared OS launches call `lifetime.start()` and fail
their native execution when persisted management has disabled the owner or restore has suspended
it. Accepted work is owned by `MiniAppRuntime`, so expiration and shutdown cancel and join cleanup.
Launch registrations and shared handlers remain passive across disable/enable; deactivation cancels
only pending owner requests and active native work. This avoids requiring `onHostLaunch` to run a
second time. The initial submission's narrower application of this rule to continued processing was
the cause of the follow-up, rather than an OS or CI limitation.

Background URLSession reconnect likewise enters through Feature lifetime admission. Disabled cold
callbacks release the host completion without constructing a session. Runtime shutdown calls
`invalidateAndCancel()` and awaits `urlSession(_:didBecomeInvalidWithError:)`; a later enabled
runtime creates a new native session using the same stable identifier. Delegate file movement is
synchronous on the dedicated serial delegate queue. Completion, all-events-finished, and invalidated
records receive monotonic sequence numbers and are buffered on `MainActor`, guaranteeing
save/result delivery before host completion even if actor tasks are scheduled out of order.

## Acceptance coverage

| Requirement | Automated/native coverage | Evidence meaning |
| --- | --- | --- |
| Two owners, registration and launch routing | Existing `MiniAppBackgroundTasksTests`; new `MiniAppContinuedProcessingTests.testTwoOwnersReceiveOnlyTheirLaunchAndProgress` | Deterministic provider routing, not OS launch |
| Refresh/processing request options and scoped cancellation | Existing `MiniAppBackgroundTasksTests` and `BackgroundTasksNative` fixture | Core regression; signed device still required for accepted native pending requests |
| Shared refresh cold recovery, batch expiration, acknowledgement failure, other-owner retention | Existing `MiniAppSharedRefreshTests` and journal tests | Durable model/provider coverage |
| Background transfer owner/profile, duplicate callback join, delegate-finish completion | Existing `MiniAppBackgroundURLSessionReconnectTests` and signed Simulator HTTP comparison | Warm host and real HTTP are proven; cold OS callback is not |
| Continued wildcard base, unique job, presentation and queue/fail strategy | New `MiniAppContinuedProcessingTests.testSubmissionRegistersUniqueComposedIdentifierAndPreservesPresentation`; Xcode native build | Core forwarding plus current SDK compilation; native admission remains device evidence |
| Continued progress, displayed title, expiration cleanup, completion once | Core tests and gated real-Feature native tests | Feature lifetime and provider behavior; system Live Activity/expiration remains device evidence |
| Rejected registration and cross-owner submit/cancel | New Core failure tests | No ownership claim or foreign cancellation on failure |
| Stop, pending cancel, cleanup join, late launch, restore, other-owner retention | `P2BackgroundNativeTests` gated Feature tests | Real Definition/lifetime path without waiting 60 seconds |
| Ordinary/shared/transfer normal entrances | Buttons and observable state in `P2BackgroundProbe`; existing Core/native HTTP tests | Real OS launch/cold callback still requires device run |
| Management disable, restore, late ordinary/shared launch, cleanup join, B retention | New gated `P2BackgroundNativeTests` | Real Feature lifetime/runtime path; injected work only removes wall-clock delay |
| URL cold admission, ordered save/completion/all-events, invalidation join, re-enable session | New native Feature test plus existing signed real-HTTP fixture | Native URLSession construction/invalidation and ordered delegate contract; OS cold launch remains device evidence |

## Shared integration changes requested from the parent

No shared file was edited in this lane. Integration needs these concrete changes in the parent's
owned files:

1. Add `Tests/P2Background/P2BackgroundProbe.swift` to the diagnostic app source list and
   `Tests/P2Background/P2BackgroundNativeTests.swift` to its native test target. Append
   `P2BackgroundProbe.definitions` at the diagnostic composition point; do not add the fixtures to
   the production Feature registry.
2. During `application(_:didFinishLaunchingWithOptions:)`, enumerate the composed definitions and
   call every `definition.onHostLaunch` before returning. The existing host launch hook is the
   intended call site; do not register these from a screen.
3. Add these exact values to the diagnostic host's composed
   `BGTaskSchedulerPermittedIdentifiers`:
   `com.jibunkit.app.p2-background-a.ordinary`,
   `com.jibunkit.app.p2-background-b.ordinary`,
   `com.jibunkit.app.p2-background.shared-refresh`,
   `com.jibunkit.app.p2-background-a.export.*`, and
   `com.jibunkit.app.p2-background-b.export.*`. The literal wildcard entries authorize each
   dynamically registered and submitted `base.UUID` job. Keep both `fetch` and `processing` in
   `UIBackgroundModes`: owner A/shared refresh use app refresh, and owner B uses processing. Apple’s
   continued-processing setup requires the permitted wildcard; no additional mode is asserted for
   that API and no optional continued-processing GPU entitlement is requested.
4. In the existing `UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:
   completionHandler:)`, forward the identifier and completion to
   `MiniAppBackgroundURLSessionReconnectRegistry.shared.handleEvents(...)`. This must run after
   launch hooks have registered factories and must not call the completion separately.
5. Reuse `Tests/Fixtures/network_server.py` and the URL injection pattern from
   `Tools/verify-background-urlsession-native.py` for the diagnostic input field. Use its
   `/hold/<token>`, `/await-start/<token>`, and `/release/<token>` routes for A-cancel/B-continue;
   do not add a synthetic URL protocol or a second server fixture.

## Verification performed in this lane

- `git diff --check`: passed with no whitespace errors. Source/reference inspection also passed.
- Swift/Core tests: not executable on this Windows worker because no Swift toolchain is installed.
- iOS SDK build and native XCTest: not executable on Windows. The native test is supplied for the
  parent's macOS/Xcode 26 integration run.
- No Simulator scheduler submission was retried. The known Xcode 26.6 / iOS 26.5 Simulator result
  in `docs/verification/2026-09-11-backgroundtasks-native-pending.md` is
  `BGTaskScheduler.Error.Code.unavailable` for both direct and wrapped requests; repeating it would
  not add evidence.
- The existing signed Simulator real-HTTP comparison in
  `docs/verification/2026-09-11-background-urlsession-native-http.md` remains valid for warm-host
  native download/cancel isolation. This change does not replace its URLSession code.

## Device acceptance and unresolved conditions

On a signed physical iOS 26 device, the parent should run the diagnostic host and distinguish the
following observations:

1. A foreground tap registers/submits a unique continued task; an actual system launch displays its
   Live Activity and advances 1 through 60 over about one minute. This is OS launch evidence. Directly invoking a handler is
   not.
2. Cancel owner A from the system interface while B runs. A must finish cleanup as unsuccessful;
   B must continue and complete. Repeat Feature-side cancellation for exact pending ownership.
3. For ordinary refresh/processing and shared refresh, accepted submission/pending request is one
   boundary; a later OS-chosen launch is separate. Capture both without treating delayed scheduling
   as a JibunKit failure.
4. Start real background downloads for A/B, background or terminate normally, and confirm the OS
   calls the app delegate, both factories reconnect without screens, and every host completion is
   released only after the corresponding delegate finish. Force-quit behavior and SideStore
   re-signing remain OS/deployment conditions, not guaranteed recovery.

Unresolved until that run: physical-device continued-processing admission/Live Activity/system
cancellation, real BGTask OS launch/expiration, background URLSession cold-launch delivery, and
SideStore re-sign identifier continuity. No iOS execution is claimed by this Windows submission.
