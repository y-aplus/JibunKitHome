# Feature-owned capture, document scanning, and code scanning

## Current integration contract

Camera-backed operations are feature-owned but acquire the shared camera resource through the host coordinator. Admit an operation only while its runtime generation is active, present consent or system UI through the feature-owned presentation boundary, and reject late callbacks after cancellation or stop.

Video with audio also requires the audio ownership and microphone-consent contracts. Copy results into feature-owned storage before dismissing temporary system resources. Build fixtures validate wiring; camera availability, permissions, interruptions, scanning accuracy, and capture quality require real-device verification.

Inject `MiniAppCaptureCoordinator.shared` into feature factories (an isolated instance in tests), create `MiniAppCaptureOwner`, and connect it from `MiniAppFeatureLifetime.configure`. Declare the feature's camera permission and feed `onSceneActivityChange` plus the injected scene connection ID into each operation. Acquisition is serialized across AR, photo, video, document, and code scanning; a conflict is surfaced instead of stealing the camera. Stop closes admission, cancels/pause-dismisses the native producer, awaits completion, and only then releases the camera. Late callbacks are filtered by owner and operation generation.

Feature code owns the concrete camera/session/controller, configuration, output types, UI, and business result. The common layer does not wrap every native option. System-presented document/code scanners go through feature-owned presentation and are dismissed on scene/lifetime stop. Copy security-scoped or controller-temporary results into the feature namespace before returning success. Cancellation and partial copy failures remove only operation staging and never publish an incomplete result.

Audio capture first acquires the compatible audio profile and microphone consent, then camera ownership; unwind in reverse order. Revalidate both generations after awaited permission or presentation. Compose camera/microphone usage descriptions and required background modes through build requirements. Unsupported hardware or unavailable scanners return an explicit unsupported result, not a simulated success.

## Japanese source notes and historical evidence

対象はiOS 26以上。JibunKitはcameraのowner別受付と寿命を管理し、撮影構成、native object、成果物、保存形式はFeatureが所有する。cameraとmicrophoneは別資源で、camera-only操作はAudio調停を要求しない。

## 接続

プロセスでは`MiniAppCaptureCoordinator.shared`をFeature factoryへ注入する。テストでは独立instanceを注入できる。`MiniAppDefinition`へpropertyは追加せず、Featureの`MiniAppFeatureLifetime.configure`で`MiniAppCaptureOwner.connect(to:)`し、`onSceneActivityChange`を`owner.receive(_:)`へ渡す。

```swift
@MainActor
func makeFeature(coordinator: MiniAppCaptureCoordinator,
                 consentStore: MiniAppConsentStore) -> MiniAppDefinition {
    let id = MiniAppID("receipt")
    let capture = MiniAppCaptureOwner(
        id: id, coordinator: coordinator,
        permissions: MiniAppAVCapturePermissionClient(),
        consent: { resource in
            consentStore.consent(for: id, permissionID: resource.rawValue) == .allowed
        }
    )
    let lifetime = MiniAppFeatureLifetime(id: id) { runtime in
        try capture.connect(to: runtime)
    }
    return MiniAppDefinition(
        id: id, title: "Receipt", systemImage: "doc.viewfinder",
        lifetime: lifetime,
        permissions: [.init(id: "camera", title: "カメラ",
            purpose: "領収書を撮影します", deniedBehavior: "scanを開始しません")],
        onSceneActivityChange: { capture.receive($0) }
    ) { _ in ReceiptView(capture: capture) }
}
```

hostは既存`FeatureBuildRequirement`で`NSCameraUsageDescription`を合成する。音声付き動画だけは`NSMicrophoneUsageDescription`も宣言する。`MiniAppPermissionDeclaration`による既存管理UIの判断を`MiniAppConsentStore.consent(for:permissionID:)`からownerの`consent` closureへ渡し、その後adapterのOS許可を要求する。store未注入、`.notDetermined`、`.denied`はいずれもOS dialogの前に拒否する。独自の永続Boolは追加せず、Feature同意とapp全体のOS許可を同じ許可として扱わない。

## operationと停止

`MiniAppCaptureOperation`の`startNative`はnative producerの開始完了後、停止完了をawaitできるclosureを返す。開始途中でthrowする実装は、まだstop closureを返せないため、自身が取得済みnative資源を先に解放する。`nativeEvents`はstreamと確定済みsession generationを一緒に返し、`restartNative`とともに中断開始／終了／runtime error値をownerへ届ける。停止は進行中のevent/restart処理をjoinしてからnativeとcameraを解放する。初期`startRunning()`失敗は`.initialization`、開始後の通知は`.runtime`で区別する。runtime errorのうちmedia services resetだけを再開候補とし、可視・同一世代・ユーザー停止前の条件を再検査する。`AVCaptureSession` graphは`MiniAppAVCaptureSessionProducer` actorから外へ出ない。

写真は`restartNative`を持ち、同一session generationの中断終了時だけ条件付きで再開する。音声付きmovieは`stopsOnInterruption: true`とし、AudioSessionが非activeな状態でcameraだけを自動再開しない。中断時にmovieのnative停止と`didFinishRecording`をjoinし、正常な部分成果なら保存、errorなら失敗表示・一時file削除とする。次の録画はユーザーが明示的に新規開始する。文書／コードscanはVisionKit提示寿命に従い、このAVFoundation自動復帰を使わない。

VisionKitは`MiniAppVisionCaptureAdapter`がMainActor上でcontrollerとoperation generationを所有し、既存`MiniAppPresentationOwner`へ提示を登録する。旧controller、多重tap、終端後のdelegateは無視する。`startScanning()`失敗は提示dismiss完了までjoinしてからthrowし、`becameUnavailableWithError`はFeatureへ失敗理由を返す。interactive dismissとnavigation dismissも同じownerのcamera予約を解放する。

inactive、background、非選択は、そのownerにactiveかつselectedな別sceneがなければ停止する。Feature停止、許可待ち取消、開始失敗でも、event/restart終了→native capture停止（未完了photoの取消とmovie `didFinishRecording`待ちを含む）→presentation dismiss完了→関連lease解放の境界をawaitする。producerへの同時stopは一つの停止処理へ合流する。ユーザー停止は復帰通知で取り消さない。古いruntime／operation／native session generationの許可結果・通知・delegate結果は採用しない。OS許可待ちの後にも全要求資源のFeature同意を再検査する。

同じcameraが使用中なら既定の`.reject`は`.cameraInUse(by:)`を返す。ユーザーが明示した切替だけ`.stopCurrent`を渡し、旧producerの停止・解放完了後に新ownerを開始する。Feature内部で一つのproducerが組むMultiCam graphは一予約として扱い、Coreが固定単眼構成へ変換しない。

## 音声付き動画

microphoneを要求するoperationには、契約固定のhookを必ず注入する。

```swift
MiniAppCaptureOperation(
    resources: [.camera, .microphone],
    acquireAudio: makeAcquireAudio(owner, stopNativeOnly),
    nativeEvents: { try await producer.events() },
    stopsOnInterruption: true,
    startNative: {
        try await producer.start()
        return { _ in await producer.stop() }
    }
)

// fixture側の親bridge
MediaCaptureProbe.makeAcquireAudio = { owner, stopNativeOnly in
    {
        let lease = try await audio.acquire(owner: owner, stopProducer: stopNativeOnly)
        return { await audio.release(lease) }
    }
}
```

operationの型は契約どおり`(@MainActor @Sendable () async throws -> (@MainActor @Sendable () async -> Void))?`。fixtureのfactoryはowner IDとnative-only stop callbackからこの型を返す。camera確保後、native開始前に呼ばれる。microphone要求でnilなら`.missingAudioHook`、取得失敗ならcamera予約を返す。camera-onlyへ暗黙downgradeしない。native adapterは共有application AudioSessionを使い、audio hook統合時に自動構成を止める。private AudioSessionで調停を迂回しない。Audio側stop callbackはproducer停止だけを行い、`owner.stop()`や同じlease解放closureを再帰awaitしない。

## fixtureと確認

`Tests/MediaCapture/MediaCaptureProbe.swift`は親が診断app targetへコピーする公開入口`MediaCaptureProbe.definitions`を持つ。親は同じMainActor上の`MediaCaptureProbe.makeAcquireAudio`へP2-1 bridge factoryを設定する。撮影Featureは実`AVCapturePhotoOutput`と音声付き`AVCaptureMovieFileOutput`経路、scan Featureは実`VNDocumentCameraViewController`と`DataScannerViewController`経路を提供する。写真Data、保持する一つのmovie URL、文書page Data、code文字列は各Feature stateが所有する。画像と文書はapp内preview、動画はAudio調停を迂回するapp内`AVPlayer`を持たずShareLinkから外部アプリで確認する。新しいmovie開始時に旧一時fileを削除し、失敗movieも削除する。画面には中断／失敗／停止、成果件数、保持値、runtime世代を表示し、音声bridge未注入時は「Audio接続未統合」と明示する。

`Tests/MediaCapture/MediaCaptureNativeTests.swift`は注入可能な実Feature factoryとVision adapterを`@testable import JibunKit_App`で検査し、停止join、A停止後のBの非初期値／同一runtime generation、同意拒否、scanner開始失敗、旧delegate拒否、外部dismissと別owner提示保持を確認する。Foundation状態試験は`Tests/JibunKitCoreTests/Capture/`にあり、競合、明示切替、stop中、許可callback遅着、scene集約、Audio解放順、世代付き中断／runtime失敗をfakeで検査する。

0.8.3の実機は代表操作へ絞った。306874fで写真・音声付き動画/背景移動停止/保存結果、a142108で文書保存/再表示/取消とQR、通常版復帰を確認済み。許可遅着/拒否、scene集約、世代、片側停止と他owner保持は実Feature/nativeおよびFoundation試験を使い、実機全組合せを反復しない。別playerとの実機同時録画、全機器/OS、AR/高度captureまで確認済みとはしない。写真初回の不明エラーは全文/再現条件不明として残す。[出荷照合](../verification/2026-09-17-0.8.3-release.md)。

Apple一次資料: [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)、[startRunning](https://developer.apple.com/documentation/avfoundation/avcapturesession/startrunning())、[runtimeErrorNotification](https://developer.apple.com/documentation/avfoundation/avcapturesession/runtimeerrornotification)、[AVCaptureFileOutputRecordingDelegate](https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate)。

外部の音声解放通知などを非同期配送する場合は、取得時の`operationGeneration`を保持し、`suspend(_:ifGeneration:)`へ渡す。旧操作の解放通知が新しい撮影を停止することを防ぐ。写真成功はfinal callbackで確定するが、停止時は未完了要求を取消し、遅着するcallbackを無視する。

文書scanの所有・取消・外部dismiss回帰は、非対応Simulatorに実`VNDocumentCameraViewController`を強制作成しない。Testing SPIから通常の`UIViewController`を注入し、本番と共有するoperation/presentation/cancel経路を検査する。公開`documentOperation`はSDK対応判定→実controller作成→delegate登録を行い、対応判定falseでは作成/提示前に`.unsupported`を返すことを別試験で確認する。実UIKit全画面回帰はCI35102558612、実VisionKit文書の成功/取消はa142108の実機結果をそれぞれ証拠とする。
