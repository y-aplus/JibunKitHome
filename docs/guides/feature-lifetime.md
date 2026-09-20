# Feature startup, shutdown, and restoration

## Current integration contract

Treat screen visibility, runtime lifetime, and durable state as separate concerns. `start` opens admission for one runtime generation; `stop` closes admission, cancels producers, drains accepted work, persists required state, and then releases resources. Late callbacks from an older generation must not mutate the restarted feature.

Restoration and migration run before normal work is admitted. Reset and removal are explicit maintenance operations, not side effects of stopping. Use the coordinated stopped-operation path for exclusive maintenance, and reopen only after it succeeds or reaches a recoverable state.

Create one `MiniAppFeatureLifetime` in the feature integration and pass it to `MiniAppDefinition(lifetime:)`. The host awaits `start()` before building the root and presents startup failure with retry. Navigation and `onDisappear` do not call `stop()`. In the configure closure, register cleanup before starting dependent work, put blocking CPU/file/database work on its own executor, and register owned tasks, HTTP clients, observations, and connections with the runtime. Cancellation of a task handle is not completion: shutdown waits for actual termination and release.

Concurrent starts share one configuration. Explicit stop cancels configuration and drains registered resources; configuration failure also drains them before returning. A retry gets a new runtime generation. Call `lifetime.stop`, not `runtime.shutdown`, from an outside coordinator; awaiting stop from an owned task would self-deadlock. The lifetime cannot forcibly terminate noncooperative work or a synchronous main-thread hang.

The host backup screen uses `effectiveRestoreLifecycle`: an explicit adapter wins, otherwise the lifetime adapter is used. Restore resumes only a feature that was running before suspension. Starts are rejected during suspension; cancellation or apply failure does not skip recovery, and an explicit stop cancels automatic resume. Connect store access to the same owner/coordinator because lifetime cannot detect unregistered transactions. `withStoppedOperation` holds restart and management while an external operation such as logout runs; its callback must not await another start/stop on the same lifetime.

## Japanese source notes and historical evidence

P0-Aの通常・生成CIで非実機条件を確認済み。対象sourceと試験範囲は[P0-A検証記録](../verification/2026-09-12-p0-a.md)を参照する。0.7.0候補の実機確認も2026-09-13に完了（[結果](../verification/2026-09-13-0.7-device-check.md)）。

## 画面と処理の寿命を分ける

`MiniAppFeatureLifetime`をFeatureのIntegrationで一つ所有し、`MiniAppDefinition(lifetime:)`へ渡す。
通常hostはroot生成前に`start()`を待ち、起動失敗の説明と再試行を表示する。
画面切替/disappearでは`stop()`を呼ばない。非選択でも必要な購読・通信・処理は継続する。
SwiftUIの[View.task](https://developer.apple.com/documentation/swiftui/view/task(priority:_:))は画面から離れると取消対象になるため、
画面からの待機とFeature所有の起動処理を分けている。

```swift
@MainActor
let lifetime = MiniAppFeatureLifetime(id: id) { runtime in
    let observations = try runtime.makeNotificationObservations()
    try observations.observe(name: .init("ExampleChanged"), extract: { _ in true }) { _ in
        // Publish this Feature's state on the main actor.
    }
    // Register owned resource cleanup before starting work that uses it.
    // Put blocking file/CPU/database work on its own actor/executor.
    try runtime.onShutdownAsync { await service.close() }
    try runtime.start { await service.processUntilCancelled() }
}
```

`service`はFeatureのサービスを表す。必要ならconfigure内で各世代の接続を作り直す。
MainActor上のconfigureに重い同期処理を置かない。DB/HTTP/購読の所有者をRuntimeへ登録し、
キャンセル後の実際の処理終了・解放まで待つ。単にTask handleをcancelしただけでは閉じたことにしない。

同時startは一つの構成処理を共有する。明示stopは構成の取消を要求し、登録済み資源の解放まで待つ。
構成失敗も登録済み資源の終了を待ってから失敗を返し、再試行は新Runtimeを使う。
`runtime`は起動中/終了中にも存在し得るので、操作開始前の`start()`とRuntimeの受付拒否を尊重する。
このRuntimeを直接shutdownする代わりにlifetime.stopを使う。所有Taskから自分のstopを待つと自己待機になるので外側の調停者から呼ぶ。
非協調処理や主スレッドの同期hangを強制終了する仕組みではない。

## 復元・移行・リセット

通常hostのBackupScreenはDefinitionの`effectiveRestoreLifecycle`を使う。
明示した`restoreLifecycle`があればそれを優先し、なければlifetimeのadapterを使う。
custom adapterはstore固有の失敗回復を含められるが、lifetimeとの接続を自分で維持する。

lifetimeのadapterは復元前に起動していたFeatureだけ再開する。未起動の保存内容を復元しても起動しない。
一時停止中のstartは拒否し、復元途中の通常起動が保存処理へ割り込むことを防ぐ。
applyで取消/失敗が起きても、復帰をcallerの取消で省略しない。復帰失敗は既存の復元失敗表示へ渡す。
一時停止中に明示stopした場合は自動再開を取り消す。

[通常保存と排他保守の入口](store-access-coordination.md)を同じowner/coordinatorへ接続する。
lifetimeだけでは未登録の保存操作を止められず、DB transactionやschema移行を肩代わりしない。
Counter/Reminderの通常Definitionもlifetimeを持つが、OSに予約済みの通知等の登録解除・データ削除とは別の操作。
それらはP0-Bでアプリ内管理へ接続し、非実機条件を確認済みである。候補の実機確認も2026-09-13に完了。

## 停止後の処理と再開を調停する

0.8.0では`withStoppedOperation`を追加した。外側の呼出元からFeatureを停止し、logout等の処理が実際に終わるまで同じlifetimeの再開・管理を待たせる。通常の保存排他は別途同じcoordinatorで取得する。callbackから自身のstart/stopや別の停止操作をawaitしない。[HTTP接続の順序と検証範囲](feature-http.md#operation-and-shutdown-order)を参照。公開0.7.0には含まれない。
