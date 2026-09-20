# Augmented reality ownership and integration

## Current integration contract

One feature owns one foreground `ARSession` through its coordinator. Start only after runtime admission and camera consent, bind callbacks to the active owner and generation, and invalidate late frames or interruption events after stop. Pause and drain the session before releasing the runtime.

AR shares the camera with capture and scanning surfaces, so acquisition must use the common camera ownership boundary and fail predictably when another owner is active. The fixtures verify integration structure; tracking quality, interruption recovery, permissions, and camera contention still require real-device testing.

The feature owns `ARSession`, concrete `ARConfiguration`, run options, frames, anchors, delegate, and renderer. `MiniAppARSessionAdapter` converts none of them; it connects start/pause and three forwarded events (`interruptionBegan`, `interruptionEnded`, `runtimeFailed`). Keep the feature delegate and forward a run-scoped `MiniAppARSessionEventForwarder`. A stale forwarder is discarded after stop/new run, and native session/frame/anchor objects never cross an actor hop.

The stop closure strongly retains the exact session, bridge, and generation until pause, event-stream termination, and camera release finish. Connect `MiniAppCaptureOwner` to lifetime, declare camera consent, forward scene activity, and pass the injected `miniAppSceneActivityID` used to start. Nonselection, inactive/background, disconnect, runtime stop, or explicit camera switching pauses; returning foreground never restarts implicitly.

Interruption marks the owner suspended without discarding the session. On end, rerun with the feature's configuration and restart options. A failed restart or nonrestartable runtime failure follows normal pause/release and fails the operation; the feature chooses reset policy and `canRestart`. All camera surfaces use `MiniAppCaptureCoordinator.shared`. Hosts inject the scene connection ID, include the camera usage description, and should not add `UIRequiredDeviceCapabilities=arkit` when supporting non-AR devices—reject via `isSupported` instead.

## Japanese source notes and historical evidence

## 採用範囲

JibunKit 1.0の通常ARは、ARKit対応端末で一つのFeatureが一つの前景`ARSession`を開始し、明示停止、通常のsession中断から復帰する範囲を対象とする。sceneの非選択・inactive・background・切断、Feature停止、camera明示切替ではsessionをpauseし、停止完了後にcamera予約を解放する。foregroundへ戻っただけでは暗黙再開せず、Featureが再び開始する。

world mapの一般保存・共有、長期relocalization、複数ARSession、ARと写真／scanの同時camera利用、background AR、高度なworld stateは対象外である。ARKit非対応とJibunKit adapter未接続は別の状態であり、非対応端末ではcamera予約を残さず`.unsupported`を返す。

## Featureが所有するもの

Featureは`ARSession`、具体的な`ARConfiguration`、`ARSession.RunOptions`、frame、anchor、delegate、描画方式（RealityKit／SceneKit／独自描画）を所有する。`MiniAppARSessionAdapter`はこれらを独自enumへ変換せず、`MiniAppCaptureOperation`へ開始・pause・中断eventだけを接続する。

初期化は明示的に行う。

```swift
let session = ARSession()
let configuration = ARWorldTrackingConfiguration()
let events = MiniAppARSessionEventBridge()
let adapter = MiniAppARSessionAdapter(
    session: session,
    configuration: configuration,
    runOptions: [.resetTracking, .removeExistingAnchors],
    restartOptions: [],
    eventBridge: events,
    isSupported: { ARWorldTrackingConfiguration.isSupported },
    installForwarder: { delegate.install($0) },
    removeForwarder: { delegate.remove(generation: $0) }
)
```

adapterは`session.delegate`を設定しない。Featureのdelegateがframe／anchorを通常どおり受け、各runで受け取る`MiniAppARSessionEventForwarder`へ次の三つだけforwardする。

- `sessionWasInterrupted` → `forwarder.interruptionBegan()`
- `sessionInterruptionEnded` → `forwarder.interruptionEnded()`
- `didFailWithError` → `forwarder.runtimeFailed(reason:canRestart:)`

forwarderはrun generationを値として固定する。旧delegate処理が保持したforwarderを停止後または次runで呼んでも、新generationへ付け替えず破棄する。bridge自身をdelegateにする場合もcallback入口でgenerationを固定してから`MainActor`へ渡すため、`Task`実行待ち中のstop/new runで再ラベルしない。delegate callback queueはFeatureの責任であり、`ARSession`、frame、anchorはactor hopを越えて保持・送信しない。

開始済みoperationの停止closureはadapterではなく、開始時のsession、bridge、forwarder generationを強く保持する。Featureがadapter参照を先に解放しても、`pause()`、event stream終了、camera解放が完了するまでcleanupを省略しない。

## sceneと寿命

Feature rootは親hostが注入する`miniAppSceneActivityID: UUID?`を読み、開始元IDを明示する。

```swift
try await owner.start(
    try adapter.operation(),
    switching: .reject,
    sceneScope: .scene(sceneID)
)
```

`.anyVisible`は既存写真／scanとの互換用既定値である。ARは`.scene(sceneID)`を使う。同じFeatureを別windowにも表示してよいが、開始元sceneが非active・非選択・切断になれば、別windowの表示状態にかかわらずそのAR操作だけを停止する。開始元以外のwindowのphase変化では停止しない。OS camera許可待ちに開始元sceneが離脱した場合も、遅い許可結果を拒否しnative sessionを開始しない。

`MiniAppFeatureLifetime`へ`MiniAppCaptureOwner.connect(to:)`を登録し、`MiniAppDefinition.permissions`にFeature所有の`camera`目的を宣言し、`onSceneActivityChange`をownerへ渡す。管理の無効化・削除・復元は既存lifetime停止をawaitするため、AR pauseとcamera解放が終わる前に所有状態を削除しない。

## camera競合

AR、写真、動画、文書／code scanは同じprocess共有`MiniAppCaptureCoordinator.shared`を使用する。

- `.reject`: 別ownerがcamera利用中なら`.cameraInUse`。既存ownerを停止しない。
- `.stopCurrent`: 現ownerのnative停止とcamera解放をawaitし、その後だけ新ownerを開始する。
- AR中断中も同一operationのcamera予約を保持する。別ownerの`.stopCurrent`ならARをpauseしてから渡す。
- permission拒否、AR非対応、開始失敗、取消、古いgeneration callbackは他ownerのruntime・保持値を変更しない。

ARと写真の同時camera利用を成功条件にしない。通常範囲は所有された直列切替である。

## 中断復帰

bridgeは一つの開始generationに対して`interrupted`、`interruptionEnded`、`runtimeFailed`を発行する。中断中はownerを`suspended(.interrupted)`にするがsessionを破棄せず、終了eventでFeature指定の同一configuration／`restartOptions`を使い再runする。再開失敗、または再開不可runtime failureは既存stop経路でpause・解放してfailedになる。古いgenerationのeventは無視する。

ARKitが自動的に回復できる具体条件やreset方針をCoreは決めない。`restartOptions`とruntime failureの`canRestart`はFeatureが選ぶ。

## 試験境界

Core unitではscene固定、許可待ち離脱、開始／停止join、callback入口generation、旧forwarder拒否、adapter解放後cleanup、中断復帰／失敗、A/B camera競合と他owner保持を検証する。AR bridgeのfake eventは所有状態の試験であり、実trackingではない。

iPad／iPhone SimulatorではARKitのcompile、通常Feature接続、unsupported拒否、fake eventを確認できる。Simulator上の`ARSession`生成、delegate呼出し、Swiftオブジェクトは実camera、実frame、実中断の証拠ではない。

物理ARKit対応端末では通常Feature UIからcamera同意とOS許可を通し、実`ARFrame`、停止後のcamera解放、写真／scanとの直列切替、OS中断と復帰、background停止後の明示再開、Feature無効化／削除時の他owner保持、同一IPA上書き／Refreshを手動シナリオで別途確認する。物理専用XCTestを通常Simulator targetへ混在させない。端末型、OS、許可状態、中断再現操作を証拠に記録する。

## 親hostに必要な接続

親所有のhostは`MiniAppSceneActivityDispatcher`の現在connection IDをrootへ公開し、SwiftUI environment `miniAppSceneActivityID: UUID?`として注入する。`Tests/P2AR/P2ARProbe.swift`と`P2ARNativeTests.swift`を診断targetへ追加し、probe definitionを通常registryへ含める。iOS条件の`Tests/JibunKitCoreTests/AugmentedReality/MiniAppARSessionAdapterTests.swift`はmacOS shared testでは実行されないため、同じsourceをiOS native test targetへ明示収録する。既存の`NSCameraUsageDescription`合成がAR targetにも入ることを生成後Info.plistで確認する。ARを任意Featureとして扱い非対応端末でもhostを提供する場合、`UIRequiredDeviceCapabilities=arkit`を一律追加せずconfigurationの`isSupported`で拒否する。`Sources/JibunKit`、`Project.swift`、workflow、plan／ledgerはこの担当変更に含めない。

## 0.8.4候補の証拠

c66b624実機ではframe受信、開始元から離脱後の停止、再入場後の明示再開・停止を確認した。camera解放の内部完了は自動試験と分け、停止表示だけから別cameraとの実handoff成功を推定しない。7e4c740/CI35325946663のnative73件にはAR世代・寿命・非対応拒否の検証を含む。実OS interruption→resumeやARとphoto/scan間の切替は実機未観測であり、採用する契約と実測結果を区別する。決定的な拒否・停止・失敗・他owner保持の組合せを、すべて人手で再試験する方針ではない。
