# Keeping the screen awake for the selected feature

## Current integration contract

A feature requests a scene-scoped screen-awake lease; it does not write `UIApplication.isIdleTimerDisabled` directly. The host computes the effective process value from currently active, selected scenes and applies it centrally.

Release the lease on deselection, scene deactivation, runtime stop, failure, and owner removal. Preserve other valid leases so one feature cannot turn off a request still needed elsewhere.

Create `MiniAppSceneIdleTimer` with the runtime and connect its `receive` method to `MiniAppDefinition.onSceneActivityChange`. Keep the scope where it receives scene events before the feature view opens. `setRequested(true)` starts a display-dependent request and `false` ends it. When rebuilding a runtime, create a new scope, replay the connection model's latest scene state, and only then admit work; a closed scope never reopens and returns `closed` from `setRequested`.

In a multi-scene host, one inactive or disconnected scene must not release another active scene's lease. Ignore events for other features. The underlying `MiniAppIdleTimer` combines leases from other operations and owners. Runtime shutdown closes the scope synchronously; standalone users call `close()` explicitly when immediate release matters. Use `preventSleep(for:)` for work that is not selection-dependent. This API does not infer sheet/detail visibility or grant background time, brightness control, or permissions.

## Japanese source notes and historical evidence

独立アプリの画面を表示している間だけ必要だった自動ロック防止を、統合後の別Featureへ持ち越さないための任意接続。`MiniAppSceneIdleTimer`は要求そのものと実際のleaseを分ける。要求中でも、そのFeatureを選択したactiveなsceneが一つもなければleaseを解除する。再選択/復帰すると要求を再適用する。

Integrationの寿命管理モデルで、Runtimeと同時にscopeを作る。

```swift
let screenAwake = try runtime.makeSceneIdleTimer(for: featureID, using: .shared)
// MiniAppDefinition(onSceneActivityChange: screenAwake.receive, ...)
try screenAwake.setRequested(true)  // display-dependent operation starts
try screenAwake.setRequested(false) // operation ends, even while hidden
```

実際のDefinitionではこのcallbackを他のscene処理と合成してよい。Viewを開く前からscene通知を受け取れる場所へscopeを保持する。Runtimeを作り直す場合は新しいscopeを用意し、モデルに保持した接続中の最新scene状態を渡してから新規操作を受け付ける。終了済みscopeへ通知を送っても再開せず、`setRequested`は`closed`を返す。

複数sceneでは、片方の非選択・inactive・背景化・接続終了だけで別のactiveなsceneの要求を解除しない。異なるFeatureのイベントは受理しない。同じFeatureの別操作や他Featureのleaseは既存の`MiniAppIdleTimer`が合成するため、このscopeの解除で消えない。Runtimeの終了hookは同期的にscopeを閉じる。単独で使う場合は明示的に`close()`する。解放時のleaseの後始末は既存のMainActor非同期fallbackであり、即時性が必要な境界では明示終了を使う。

表示依存ではない操作向けには従来の`preventSleep(for:)`を維持する。既存要求の意味を変更せず、選択依存の方針を必要とするFeatureが本scopeを選ぶ。任意のsheet被覆や画面内の詳細Viewの可視性は判定しない。OS権限・背景実行時間・画面輝度の管理でもない。

[Apple isIdleTimerDisabled](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled)は必要がなくなったらfalseへ戻すことを求める。音声再生継続のためだけに画面を点灯し続ける必要はない。[検証記録](../verification/2026-09-11-scene-idle-timer.md)。
