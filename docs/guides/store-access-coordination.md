# Coordinating normal store access and restoration

## Current integration contract

All normal reads and writes acquire a store-access reservation tied to the active owner and runtime generation. Maintenance operations such as migration, restore, reset, snapshot, and removal close admission and wait for accepted work to drain before obtaining exclusive access.

Do not treat actor serialization alone as a lifecycle guarantee: an operation may suspend while stop or maintenance begins. Validate its reservation before committing, reject stale generations, and reopen admission only after the durable store is in a coherent state.

Wrap every UI, App Intent, synchronization, and callback entry point in `MiniAppRestoreCoordinator.shared.withStoreAccess(for:operation:)`, using the same coordinator and feature ID as backup and restore. Ordinary operations for one feature may run concurrently; the database engine still owns transactions, pools, and read/write exclusion. Closures and results are `Sendable`, but the API does not make a non-Sendable connection safe across executors.

Restore or snapshot returns `Conflict` before stopping/exporting when any ordinary operation remains. While exclusive work runs, new ordinary operations for that owner also receive `Conflict`; other owners continue. Cancellation before admission skips the closure. Cancellation after admission keeps the reservation until the closure returns or throws, so the store must finish or roll back safely. Do not start an un-awaited task and return from the protected closure. There is no unbounded queue or automatic retry.

Code already inside exclusive export, stop, apply, resume, or recovery calls lower-level storage directly and must not reacquire `withStoreAccess`. Ordinary work cannot upgrade itself to restore. This process-local contract cannot detect unregistered writes, widget processes, stale callbacks, open transactions, or retained connections; pair it with `restoreLifecycle` before replacing files.

Run migration and reset with `withStoreMaintenance(for:lifecycle:operation:)`. It rejects conflicts immediately and holds the owner reservation through stop, operation, and resume. Cancellation and transaction rollback after operation start remain store responsibilities; resume failure is reported as `MiniAppRestoreLifecycle.Failure`. In Records integration, inject `RecordStoreOperationBoundary`: reads/writes/import/attachments are ordinary operations, migration/reset are maintenance, while backup export/apply use lower-level methods because the outer coordinator already owns the reservation.

## Japanese source notes and historical evidence

Featureの通常の読書きは、`MiniAppRestoreCoordinator.withStoreAccess(for:operation:)`で同じ保存先の復元・snapshotと調停できる。DBを変更したり通常の読書きを一つずつ直列化したりする必要はない。

```swift
let value = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: context.id) {
    try await database.readCurrentValue()
}

try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: context.id) {
    try await database.updateEntry(entry)
}
```

`database`はFeature所有のactor等、元のエンジンの並行実行契約を満たす保存層である。このAPIは非SendableなDB接続を別executorへ安全に渡す仕組みではない。closureと返却値はSendableであり、MainActor所有の保存層ならそのactorを経由する。

## 受付の契約

- 通常操作同士は同じFeatureでも並行して入れる。DB内部のトランザクション・接続pool・read/write排他はエンジンが管理する。
- 一件でも通常操作が残っているFeatureへの復元・snapshotは、stop/exportを呼ぶ前にConflictを返す。バックアップ画面はデータ使用中として再試行を案内する。
- 復元・snapshot中は同じFeatureの新しい通常操作をConflictで拒否する。他Featureの操作は進められる。
- 受付前に取消済みならoperationを呼ばない。受付後に取消されても、operationが戻る/throwするまで予約を保持する。途中のDB処理を安全に終えるかrollbackする責任は保存層にある。
- 失敗時もoperationの終了で予約を解放する。無期限のqueueや自動再試行は追加しない。通常操作側のConflictは、その操作のUI/呼出元が使用中として扱う。

## 接続時の注意

バックアップprovider/復元planと同じcoordinator・Feature IDを使い、UI、App Intent、同期処理等の入口で漏れなく登録する。呼出元独自のcoordinatorへ分けると共有バックアップとの排他が成立しない。closureから未awaitのTaskやcallbackを起動して即座に戻ると、その後の仕事は保護されない。callback型APIは完了までawaitできる形へ接続する。

既に排他的に実行されるexport、stop、apply、resume、recoverAfterFailedStopの内部から、同じFeatureの`withStoreAccess`を再度呼ぶとConflictになる。これらは予約済みとして低層の保存操作を直接使う。通常操作のclosure内から同じFeatureの復元を呼んでもConflictになり、暗黙の昇格は行わない。

プロセス内の協調契約である。未登録の書込み、別processのWidget writer、旧callback、DBの保持接続や開いたtransactionを自動検出しない。復元前の全接続終了には[restoreLifecycle](../runtime-restore-integration.md)も必要であり、通常操作が0件というだけでファイルを安全に置換できるとは限らない。

[検証記録](../verification/2026-09-11-store-access.md)はnative SQLiteと二Featureの共有画面を対象とする。全DBやD07全体の完成判定にはしない。

## 移行・リセット等の排他的な保守

通常操作と同時に走らせられない移行・リセットは、同じcoordinatorとownerで`withStoreMaintenance`へ渡す。値を返す操作にも使える。接続を閉じる必要がある保存層はrestoreと同じlifecycleを渡し、予約はstopからapply、resumeが終わるまで保持される。

```swift
let changed = try await MiniAppRestoreCoordinator.shared.withStoreMaintenance(
    for: context.id,
    lifecycle: featureLifetime.restoreLifecycle
) {
    try await database.migrateIfNeeded()
}
```

受付前に取消済みならstopもoperationも実行しない。operation開始後の取消、transaction完了、rollbackは保存層の責任であり、resume失敗はrestoreと同じ`MiniAppRestoreLifecycle.Failure`で報告される。既存の通常操作または同ownerの復元・snapshot・保守があれば即座にConflictを返し、自動待機や暗黙の昇格はしない。

RecordsFeatureはCoreをimportせず、`RecordStoreOperationBoundary`を初期化時に受け取る。standaloneでは既定の直接実行、hostでは`RecordsStoreOperationBoundary`を注入する。`records`、保存、削除、添付の追加・読出し・import・copy・削除は通常操作、`migrateIfNeeded`と`reset`は保守操作として登録される。一方、backup providerのexport/applyは外側ですでにowner予約を持つため、snapshot用の低層操作を直接呼び、同ownerの予約を二重取得しない。
