# Database file placement and engine responsibilities

## Current integration contract

Place database files under the feature's `MiniAppFiles` namespace. The database engine owns its auxiliary files, locking, and recovery; callers must not copy or delete a live database as if it were a single ordinary file. Coordinate open, maintenance, snapshot, reset, and removal through the shared store-access boundary.

For SQLite, a consistent snapshot must account for WAL and shared-memory state by using the engine's backup/snapshot facilities after admission is closed and active operations are drained. A runtime stop does not imply that every durable database should be deleted.

Create the database URL with `MiniAppFiles.shared(context:)`, call `prepareDirectory()`, and pass `fileURL(named:)` to the feature's native database configuration. `MiniAppFiles` validates the file name and isolates the directory; it does not manage schemas, WAL files, pools, or connections. Keep engine-created sidecars in that directory. A deliberately shared database needs an explicit URL and a single agreed connection owner.

Use `withStoreAccess` to coordinate ordinary reads and writes with backup or restore. Before replacement or deletion, close every connection, statement, and external writer. A successful `sqlite3_close_v2` call may defer closure, while `sqlite3_close` can return `BUSY`; neither should be treated as proof that all users have stopped. Put fallible database shutdown in `MiniAppRestoreLifecycle.stop` after runtime draining. On failure, abort replacement and either restore the existing connection in `stop` or implement `recoverAfterFailedStop`; report restoration failure separately from recovery failure. After a clean restore, reconnect `resume` to the restored store.

## Japanese source notes and historical evidence

JibunKitへ統合してもDBエンジンを置き換える必要はない。`MiniAppFiles`でFeature専用URLを作り、SQLite・GRDB・Core Data等、そのエンジンの接続設定へ渡す。同じローカルDB名でもFeatureごとのディレクトリへ分かれる。

```swift
let files = try MiniAppFiles.shared(context: context)
try files.prepareDirectory()
let databaseURL = try files.fileURL(named: "store.sqlite")
// Pass databaseURL to the Feature's native database configuration.
```

`fileURL`はファイル名を検査するが、DB接続・schema・WAL・共有接続poolを管理するAPIではない。エンジンが作るsidecarもこのURLと同じFeatureディレクトリに置く。明示的な共有DBを使う場合だけ、共有するURLと接続所有者をIntegrationで合意する。別Featureの書込みと衝突しないことと、同じDBを使う複数writerが整合することは別の条件である。

通常のDB読書きと共有バックアップの交差は、[withStoreAccess](store-access-coordination.md)で調停できる。DB接続が生きていることと、現在実行中の読書きがあることを区別し、ファイル置換時には下記の停止も行う。

## SQLiteのsnapshotと終了

稼働中のWAL形式DBは、主ファイルだけを`MiniAppFiles.read/write`でコピーしてバックアップにしない。SQLiteの[Online Backup API](https://www.sqlite.org/backup.html)等、エンジンが提供する整合したsnapshotをFeature adapterから使う。WAL/SHMはエンジンが扱う状態であり、無関係なデータファイルと同じ置換手順にはできない。[WALの仕様](https://www.sqlite.org/wal.html)。

ファイルの置換や削除に入る前に、そのFeatureの全接続・statement・外部writerが終了したことを確かめる。SQLiteの`sqlite3_close`は未解放statementがあるとBUSYを返し、接続を閉じない。`sqlite3_close_v2`は終了を遅延できるので、呼出しが成功しただけで即時にすべての利用者が止まったとは判定しない。[SQLite close仕様](https://www.sqlite.org/c3ref/close.html)。

`MiniAppRuntime.shutdown()`は登録Taskとcleanupを待つが、任意DBの接続を発見せず、現在のcleanup hookはエラーを返さない。失敗し得るDB終了は、Featureのthrowingな`MiniAppRestoreLifecycle.stop`内で、Runtime終了待ちの後に明示的に検査する。失敗したらthrowして復元/ファイル置換へ進めない。ただし、Runtime終了後のthrowだけではFeatureが使えなくなる。stop自身で回復するか、`recoverAfterFailedStop`を登録し、残った接続が利用可能か確認してから新しいRuntimeと受付を用意する。回復にも失敗した場合は未復元と回復失敗を区別して報告する。

SQLiteのBUSY closeでは元の接続が生きているため、再接続を重ねる前にその接続と未解放statementを調べる。複数接続の一部だけが閉じた場合などは、そのDB adapterが途中状態を管理する。正常な停止後の`resume`では復元後の保存層へ再接続する。全DB用の自動復元adapterが完成しているという意味ではない。

[native SQLiteの検証記録](../verification/2026-09-11-sqlite-isolation.md)はSQLiteの具体例である。Core Data/SwiftData/他DB、App Groupの別process writer、iOSファイル保護・署名変更の条件へ成功を拡大しない。
