# Runtime and restore integration

## Available behavior

The shared backup screen stops each selected feature, applies its prepared restore, and resumes it. Restore and snapshot operations for the same feature are rejected when they overlap, without stopping unrelated features. `MiniAppRuntime` closes task admission and waits for accepted tasks plus synchronous and asynchronous cleanup.

This contract does not choose a database engine. Feature code still closes database connections, unsubscribes observers, and blocks synchronous or callback-based writes. Work that was never registered with the runtime or store coordinator cannot be discovered automatically.

## Connect an owner through resume

1. Keep one feature owner alive longer than temporary view instances. It holds the current runtime and store; multiple screens for that feature share it.
2. Immediately after acquiring a resource, register its release with `onShutdown` or `onShutdownAsync`. Only then register dependent work with `start`. Tasks must cooperate with cancellation and actually finish.
3. Route non-UI write entry points through the same owner. Runtime shutdown closes task admission, but the owner must also close synchronous and external-callback admission. Wrap ordinary store work in `withStoreAccess` so restore and snapshot conflicts are rejected before execution; see [store access coordination](guides/store-access-coordination.md).
4. In `MiniAppDefinition.restoreLifecycle.stop`, close feature admission and `await runtime.shutdown()`. Cleanup hooks run in reverse registration order after owned tasks finish. Never await the same shutdown from one of its owned tasks or cleanup hooks.
5. A backup provider's `prepare` validates and stages only. Its returned `apply` replaces storage after stop has completed. The shared Files/JSON flow follows this order.
6. In `resume`, reconnect the store, construct a new runtime generation, replace the owner's runtime reference, and reopen admission. Views obtain the runtime through the owner rather than retaining an old generation.
7. A direct restore-plan caller passes hooks to `apply(lifecycles:)`. The shared backup screen already gathers them from definitions and needs no host-specific feature switch.

[`LifecycleProbeIntegration.swift`](../Tests/TemplateIntegration/LifecycleProbeIntegration.swift) is a two-feature CI example. `LifecycleProbeState` owns runtime replacement across `start`, `shutdown`, and `resumeAfterRestore`; its definition registers both provider and lifecycle, and `applyRestored` verifies shutdown before mutation. It is not a database adapter. A real database must implement connection drain/reopen, transactions, and external-process locking. Runtime/plan behavior is covered by [`MiniAppRuntimeTests`](../Tests/JibunKitCoreTests/MiniAppRuntimeTests.swift).

## Failure and conflict behavior

| Condition | Shared-path behavior | Feature responsibility |
| --- | --- | --- |
| Same owner overlaps restore, snapshot, maintenance, or registered ordinary work | Return `Conflict` before stop/apply | Use the same coordinator for the same store |
| `stop` throws | Await optional `recoverAfterFailedStop`; do not apply or resume | Register recovery or restore usability inside `stop` |
| Recovery after failed stop also throws | Report `stopAndRecovery` with both causes | Diagnose partially stopped resources and keep admission safe |
| `apply` throws | Attempt resume; do not modify later features | Recover from partially changed storage |
| `resume` throws | Report applied data separately from restart failure | Restrict use and provide reconnection recovery |
| Cancelled before admission | Change nothing | Do not create a cancellation-bypassing entry point |
| Cancelled between multiple features | Finish recovery/resume for work already started, then stop before the next feature | Do not describe completed work as globally rolled back |

`recoverAfterFailedStop` handles a resource left in a partial stop and is distinct from normal `resume`. Even when recovery succeeds, the restore remains failed and later features are not started. The coordinator reservation remains held until recovery completes, including after caller cancellation. Inspect which database connections remain alive before constructing replacements; do not recreate everything blindly in a mixed state. See [failed-stop recovery evidence](verification/2026-09-11-restore-stop-recovery.md).

## Evidence and remaining limits

- Unit coverage verifies admission closure, task drain, reverse cleanup, concurrent shutdown joining, duplicate reservation rejection, cancellation, snapshot conflicts, and continued operation of another owner.
- The CI UI covers selected restore, four failure paths, A runtime restart, and preservation of B tasks/data.
- Device evidence covers Counter JSON export, import, selection, and overwrite restore.
- P0-A connects Records JSON/attachments and native SQLite to ordinary access, stop/resume, migration, and reset. See [P0-A evidence](verification/2026-09-12-p0-a.md) and the separate [SQLite evidence](verification/2026-09-11-sqlite-isolation.md).

Adapters for every database and automatic coverage of unregistered writers, subscriptions, and other-process writers are not claimed. Current release evidence is in the [0.7.0 release record](verification/2026-09-13-0.7-release.md); older successful and failed Files flows remain historical evidence, not current blockers. Overall scope remains tracked in the [coexistence ledger](coexistence-ledger.md).
