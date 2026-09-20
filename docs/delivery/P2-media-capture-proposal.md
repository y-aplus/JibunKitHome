# P2-2 撮影・文書／コードscan設計提案

> 履歴注記: 本文は実装前の設計提案であり、未確定接点と実機予定は当時の記録である。現在の採用範囲・証拠は[plan.json](plan.json)、[status](../status.md)、[captureガイド](../guides/capture.md)を優先する。

対象は0.8.2（`52a29ff`）上のP2-2である。Featureが撮影構成・成果物・業務判断を所有し、JibunKitはowner別の利用受付、寿命、可視性、取消、解放だけを補う。高度な同時captureとAR world stateは対象外だが、全撮影を一律排他にせず、OSが許す別資源・別ownerの処理は保持する。

## 公開API候補

```swift
public enum MiniAppCaptureResource: Sendable, Hashable {
    case camera
    case microphone
}

public enum MiniAppCaptureSuspension: Sendable, Equatable {
    case sceneInactive, background, notSelected, presentationEnded
    case systemInterruption(reason: Int?)
}

public enum MiniAppCaptureState: Sendable, Equatable {
    case idle
    case requesting(Set<MiniAppCaptureResource>)
    case ready
    case running
    case suspended(MiniAppCaptureSuspension)
    case failed(MiniAppCaptureFailure)
    case stopped
}

public enum MiniAppCaptureFailure: Error, Sendable, Equatable {
    case featureConsentDenied(MiniAppCaptureResource)
    case osPermissionDenied(MiniAppCaptureResource)
    case unsupported
    case unavailable
    case configuration(String)
    case runtime(String)
    case audioRequestRejected(String)
    case presentationEnded
}

@MainActor
public final class MiniAppCaptureOwner {
    public nonisolated let id: MiniAppID
    public private(set) var state: MiniAppCaptureState

    public init(id: MiniAppID)
    public func connect(to runtime: MiniAppRuntime) throws
    public func receive(_ activity: MiniAppSceneActivity)
    public func start(_ operation: MiniAppCaptureOperation) async throws
    public func suspend(_ reason: MiniAppCaptureSuspension) async
    public func stop() async
}

public struct MiniAppCaptureOperation: Sendable {
    public enum Kind: Sendable { case avFoundation, documentScanner, dataScanner }
    public let kind: Kind
    public let resources: Set<MiniAppCaptureResource>
    public let resumesAutomatically: Bool
    // native factory/result callbacksは実装時にisolationを保持する別型で確定する。
}
```

`MiniAppCaptureOwner`はFeatureごと・runtime generationごとに一つ置く。`MiniAppDefinition`へのoptional `capture`、または既存`onSceneActivityChange`から`receive`を呼ぶ接続を親が選ぶ。許可宣言は既存`MiniAppPermissionDeclaration`の安定ID（例 `camera`, `microphone`）を用い、Feature同意を確認してからOS許可を個別に要求する。OS許可はapp全体、同意と受付はFeature単位であり、片方の拒否・取消は他ownerや要求していない資源を変更しない。

## 所有とactor

- `MiniAppCaptureOwner`、VisionKit controller、delegate、提示handleは`@MainActor`所有とする。Appleの現行宣言では`DataScannerViewController`とdelegateは`@MainActor`である。一方、現行Web資料で`VNDocumentCameraViewController`自体のSwift isolationは確認できなかったため、UIKit操作としてMainActorに閉じる設計判断であり、SDK宣言確認済みとは扱わない。
- `AVCaptureSession`、inputs/outputs/deviceと通知tokenは、Featureが供給する内部`SessionWorker`が専用serial executor/queue上で生成から破棄まで所有する。`startRunning()`はblockingなのでMainActorでは呼ばない。native objectを`Sendable`な公開値やactor間callbackへ渡さず、結果はFeature定義の`Sendable` valueまたはMainActor callbackへ変換する。Swift 6のimport時sendabilityとcustom executorの正確な型は実装SDKでcompile確認するまで未確定で、安易な`@unchecked Sendable`を公開契約にしない。
- VisionKit提示は既存`MiniAppPresentationOwner.begin(.uiViewController)`に登録し、全delegate終端（成功・取消・失敗）でdismiss完了後に`didEnd`する。Appleは文書scannerの全delegate callbackでapp側dismissを要求している。DataScannerは提示前に`isSupported`と`isAvailable`を分けて判定し、`startScanning()`失敗と`becameUnavailableWithError`を通常失敗として扱う。
- Featureはcapture成果物と一時ファイルの保存／破棄を所有する。JibunKitは成功成果物を横取りせず、停止時は新規callback受付を閉じ、generation tokenの一致する処理だけを配送する。

## 状態遷移と復帰

`idle → requesting → ready → running`を通常経路とする。同意拒否、OS拒否、非対応、構成失敗は`failed`でnative objectを残さない。`running`中にscene inactive/background、非選択、提示終了、OS中断を受けると、まず新規結果を閉じ、scan/sessionを停止してから`suspended`へ進む。Feature停止は理由を問わず`stop()`をjoinし、observer/delegate/input/output/controller、提示handle、音声調停leaseの順序依存を解消して`stopped`にする。古いgenerationのdelegate・通知・async結果は無視する。

復帰は「同じruntime generation」「Feature同意とOS許可が現在も有効」「少なくとも一つの接続sceneがactiveかつselected」「提示ownerが接続中」「ユーザー取消や明示停止ではない」をすべて満たす場合だけ行う。AVFoundationの`interruptionEndedNotification`は再開可能性の通知であって開始命令ではない。runtime errorは再構成可能なものだけFeature方針で一度再構成し、それ以外は`failed`とする。VisionKitのユーザー取消・文書保存完了・コード選択完了は終端であり自動再提示しない。background cameraの特別capabilityを暗黙に有効化せず、通常は停止する。

複数sceneではownerが受けたactivityをscene ID別に集約する。あるsceneのdisconnectだけで別のactive/selected sceneを止めない。逆に単一sceneの非選択をFeature停止と同一視せず、撮影UIの可視要件によりsuspendする。別owner Bのstate、presentation、permission decision、runtime generationには触れない。camera競合はOSの中断／利用不可を各ownerへ返し、JibunKit独自の永久lockや先勝ち固定業務モデルを導入しない。

## 音声付き撮影

`.microphone`を含むoperationは、camera許可とは別にFeature同意と`AVCaptureDevice.authorizationStatus(for: .audio)`を通し、P2-1のAudioSession調停から「録音用途・必要mode/options・開始／停止完了」のleaseを得てからaudio inputとsessionを開始する。`AVCaptureSession.usesApplicationAudioSession`は既定どおり共有sessionを使い、調停済み設定を勝手に上書きしないため`automaticallyConfiguresApplicationAudioSession = false`を候補とする（組合せの実機確認後に確定）。`usesApplicationAudioSession = false`でprivate sessionへ逃がすことは、Appleもappの再生を中断し得るとしているため禁止する。音声lease拒否はcamera-onlyへ暗黙downgradeせず、Featureが明示的に別operationを選ぶ。停止時はAV capture停止完了後に自ownerのleaseだけを解放し、別ownerの再生・録音を停止しない。

## 実Feature例

1. **Receipt Feature**: `camera`同意後、`VNDocumentCameraViewController.isSupported`を確認してsheet提示する。成功時は`VNDocumentCameraScan`の各pageをFeature保存形式へMainActor上でコピーし、dismiss完了後に保存taskへ渡す。取消・失敗・Feature無効化ではAのcontrollerと一時成果だけを解放し、録音中のBを保持する。
2. **Inventory Feature**: `DataScannerViewController`をbarcode型で構成し、active/selectedかつ提示中だけ`startScanning()`する。tapされたコードをSendable文字列へ変換して一件採用後に停止・dismissする。電話着信、Control Center、background、`becameUnavailableWithError`ではscanを止め、条件を満たすOS中断終了だけ再開候補にする。Aの取消・カメラ不可でもBの保存処理とpermission decisionは不変とする。

AVFoundation写真／動画Featureも同じownerを使うが、具体的なpreset、output、撮影UI、保存形式はFeature所有であり固定しない。

## 検証

自動試験はfake permission/presentation/session/audio leaseで、資源別同意とOS拒否、cameraのみ／camera+microphone、同時要求の片側失敗・取消、scene集約、background・非選択・system interruption、復帰条件、停止join、逆順解放、二重停止、古いgeneration callback拒否、runtime error、VisionKit三終端、DataScanner非対応／利用不可を状態モデルで検査する。さらに上記2 Featureを通常`MiniAppDefinition`、`MiniAppFeatureLifetime`、`MiniAppPresentationOwner`へ接続し、A停止・取消・再開中もBの非初期state/runtime/presentation/consentが保持されることを検査する。SDK型を使うcompile fixtureはiOS targetで行うが、この設計commitではCIを実行しない。

最小実機項目は、(a) camera許可の許可／拒否とSettings変更後の再試行、実写真または文書scanの成功／取消／解放、(b) 対応端末で実barcode scan、background/foregroundまたはOS中断後の表示可能な停止／復帰、(c) 音声付き短時間撮影とP2-1 lease競合・停止後の他owner音声保持、(d) Feature A切替／無効化後もBの非初期状態を保持、である。Simulatorは状態・提示結線用で、実camera、A12要件、OS許可UI、音声経路の証拠にしない。上書き／Refreshは同じnative契約が変わらない限り既存P2実機束へまとめる。

## 親／P2-1へ要求する未確定接点

- 親: optional capture ownerの`MiniAppDefinition`格納方法、scene activity集約をcore共通化するかFeature内に置くか、Info.plistの`NSCameraUsageDescription`/`NSMicrophoneUsageDescription`をFeature宣言からhost診断する契約。
- 親: presentation dismissとcapture停止のどちらを先に開始し、両方をruntime shutdownがjoinするかの統合順序。提案は受付閉鎖→native停止→dismiss完了→delegate/observer破棄。
- P2-1: owner付きaudio request/lease、競合理由、切替承認、停止完了待ち、OS interruption配送の最小API。capture側はそのAPIを迂回するcategory設定を持たない。
- 実装担当: iOS 26 SDKで`AVCaptureSession`関連型、VisionKit delegate、factory/callbackのSwift 6 isolationをcompile確認し、未確認属性を文書へ反映する。

## 確認したApple一次資料（2026-09-16）

- [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession): serial queue推奨のblocking `startRunning()`、停止、構成、実行／中断／runtime error通知、共有AudioSession関連property。
- [AVCaptureDevice authorization](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)): video/audio別の`authorizationStatus(for:)`とasync `requestAccess(for:)`、usage description要件。
- [VNDocumentCameraViewControllerDelegate](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontrollerdelegate) / [isSupported](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller/issupported): 成功・取消・失敗とapp側dismiss、端末対応判定。
- [DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller) / [delegate](https://developer.apple.com/documentation/visionkit/datascannerviewcontrollerdelegate): `@MainActor`、`isSupported`（A12以降、visionOS不可）、`isAvailable`、throwing `startScanning()`、`stopScanning()`、利用不能callback。
- [usesApplicationAudioSession](https://developer.apple.com/documentation/avfoundation/avcapturesession/usesapplicationaudiosession): 既定trueとprivate audio session利用時のapp内再生中断リスク。
