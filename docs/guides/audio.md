# AudioSession / Now Playing integration

## Current integration contract

Use one process-level audio coordinator and native driver. Each feature submits a typed playback/recording requirement; the coordinator computes a compatible effective session rather than allowing features to mutate `AVAudioSession` directly. Reject incompatible combinations, serialize activation changes, and close new admission before draining work during shutdown.

The active owner supplies Now Playing metadata and remote-command handlers. Clear both when ownership ends, and reject stale callbacks by owner and generation. Microphone access requires the feature's consent declaration and host-composed usage description. Route interruptions and media-service resets through the coordinator, then reapply only still-valid requirements. Build fixtures do not replace real route, interruption, Bluetooth, lock-screen, or background testing.

Compatibility is the intersection of every owner's explicit profile; never promote a category or union options implicitly. On `.conflict`, product UI either keeps the current owner or calls `resolve(_:as:)`. Start the replacement only after the old producer finishes stopping. Report `.partialStop` with stopped and surviving owners, and reject an old decision as `.staleConflict`. Preserve Apple category/mode strings and option raw bits so future native values pass through.

`release` awaits the registered producer stop and must not be recursively called by that stop closure. External release joins the current transaction; competing starts/changes return busy. A profile-change failure reapplies and activates the old profile; distinguish driver failure from recovery failure. On deactivation failure, retain the stopped lease, retry with `recoverSession()`, and have lifetime wait through `waitForRelease` rather than claiming shutdown success or spinning retries.

Update intent on play/record and on user stop, remote pause, or route loss. After interruption, the feature rechecks lifetime, scene, and producer state and explicitly calls `reactivate`; a new user action uses `activateForUserAction`. A media-services reset ends old player/Now Playing state and creates new native objects only after reactivation. `MiniAppNowPlayingOwner.invalidate()` closes admission, removes only its tokens, and joins in-flight delivery; a synchronous command result means enqueue success, with the actual Boolean result delivered separately. Shutdown order is producer stop, Now Playing invalidation, then lease release.

Recording checks feature consent and `AVAudioApplication.requestRecordPermission()` separately, then revalidates generation after awaiting permission. Compose `NSMicrophoneUsageDescription`; request `UIBackgroundModes = ["audio"]` only when needed. No legacy permission fallback is claimed.

## Japanese source notes and historical evidence

`MiniAppAudioSessionCoordinator` は一つのhost processで一個を共有する。productionでは一個の`MiniAppNativeAudioSessionDriver`を作り、coordinatorへ注入して`connect(to:)`する。テストは独立driverを注入する。Featureはplayer/recorder、録音物、再生位置、再開判断を所有し、coordinatorは`AVAudioSession`構成だけを所有する。

```swift
let audio = MiniAppNativeAudio.coordinator // Capture bridgeも同じinstanceを注入する

let admission = try await audio.acquire(
    owner: id,
    request: MiniAppAudioRequest(
        acceptableProfiles: [.init(category: .playback, mode: .spokenAudio)],
        purpose: "番組を再生"
    ),
    stop: { await feature.stopPlayerAndWait() },
    receive: feature.receiveAudioEvent
)
```

互換性は全ownerが明示したprofileの積集合だけで決まる。暗黙のcategory昇格やoption和集合は行わない。`.conflict`では製品UIが継続か`resolve(_:as:)`による明示切替を選び、coordinatorは旧producerのstop完了後だけ新requestを開始する。stop失敗後の`.partialStop`には実際に停止済み・残存するownerが入る。古いconflictは`.staleConflict`となり、新世代を停止しない。

Category/ModeはApple標準文字列、route policy/optionsは標準raw bitsを保持するSendable wrapperである。named constantsは便利APIにすぎず、`init(rawValue:)`で将来追加された標準値・bitも欠落なくnative adapterへ渡る。profile変更失敗は旧profileを再適用・activateしてrollbackし、rollback失敗は`.driverChangeFailed`と`.recoveryFailed`で明示する。

`release`自身が登録済みstopをawaitする。stop closureはnative producerの停止完了までを担当し、同じcoordinatorの`release`を再帰awaitしない（`.stopReentry`/`.coordinatorBusy`）。別transaction中の外部releaseはidle境界をjoinする。他の開始/設定変更はbusyを返し、停止が待つremote commandとの相互待ちを避ける。deactivate失敗時は停止済みleaseと`.deactivationFailed`を保持し、同じleaseの再試行はproducerを二重停止しない。すべてのproducerが停止済みなら`recoverSession()`でdeactivateを再試行してleaseを除去できる。lifetimeは失敗後に`waitForRelease`で明示的な解放/復旧を待ち、短周期retryや終了成功扱いをしない。恒久的なnative stop失敗では終了境界も完了せず、Feature側の回復が必要となる。解放後は`.released`をそのownerへ送り、外部切替による停止もFeatureへ伝える。

Featureは再生・録音開始時に`updateIntent(.active, for:)`、ユーザー停止、remote pause、headphone抜去ではそれぞれ`.stoppedByUser` / `.stoppedForRouteChange`を設定する。interruption endの候補後は、Featureがlifetime/scene/producer状態を確認して`reactivate(_:)`を明示的に呼ぶ。beginだけでは成功しない。新しいユーザーPlay/Recordは`activateForUserAction(_:)`を使い、過去の停止intentを明示的に更新する。media-services resetでは旧player/Now Playingを終了し、`reactivate(_:)`後にnative objectを新規生成する。通知だけで旧objectを再生しない。

Now PlayingはFeatureごとに`MiniAppNowPlayingOwner`を持つ。session固有のinfo center/command centerを使い、ownerは登録tokenだけを削除する。同期remote handlerの`.success`はMainActorへのenqueue成功であり、操作完了ではない。実操作のBool結果は別の`onCompletion`へ届く。async `invalidate()`は受付を閉じてtokenを除去し、既に実行中の配送をjoinしてから返る。handler自身から同ownerをinvalidateする再帰は`.recursiveInvalidation`で拒否する。停止時はplayer停止、`invalidate()`完了、audio lease解放の順にする。

録音Featureは`MiniAppPermissionDeclaration`とhostの`MiniAppConsentStore`によるFeature ID別同意、および`AVAudioApplication.requestRecordPermission()`によるOS許可を別々に扱う。許可await後にはFeature操作世代を再検査し、停止済みなら開始しない。iOS 26のみのため旧permission API fallbackはない。親は`FeatureBuildRequirement`で`NSMicrophoneUsageDescription`を合成する。背景再生が必要なFeatureは同じ仕組みで`UIBackgroundModes = ["audio"]`を要求する（専用entitlementではない）。

撮影側の接続は次のhookを使う。camera予約後/native開始前に呼び、返ったclosureはその取得分だけを解放する。audio側stop callbackは撮影producer停止完了までで、closureを再帰的に呼ばない。

```swift
acquireAudio: (@MainActor @Sendable () async throws
    -> (@MainActor @Sendable () async -> Void))?
```

診断hostには`Tests/MediaAudio/`の支援Swiftをapp targetへコピーし、`MediaAudioProbe.definitions`をregistryへ追加する。native test targetには`MediaAudioNativeTests.swift`を入れ、`@testable import JibunKit_App`を有効にする。fixtureは外部素材不要のローカルWAVをloop再生する。自動testは注入permission/recording backendで遅着、停止待ち、失敗、中断再開、Bの世代保持を検査し、microphone未許可をskip成功にしない。

実機は代表OS操作へ絞る。306874fで実録音/録音再生、背景、Siri割込み後の明示再開、Lock Screen pause/play、a142108でイヤホン抜去停止と通常版復帰を確認済み。通話全種別、有線/Bluetooth全機器やControl Center全操作の確認とはしない。状態/取消/失敗/他owner保持の組合せは自動試験を使う。[0.8.3の出荷照合](../verification/2026-09-17-0.8.3-release.md)。
