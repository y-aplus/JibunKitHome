# P2-1 AudioSession / Now Playing 設計提案

> 履歴注記: 本文は実装前の設計提案であり、compile未確認や実機予定は当時の状態である。現在の採用範囲・証拠は[plan.json](plan.json)、[status](../status.md)、[音声ガイド](../guides/audio.md)を優先する。

## 結論と境界

対象は iOS のプロセス共有 `AVAudioSession` の調停と、Feature ごとの `MPNowPlayingSession` / remote command 所有である。player、recorder、録音ファイル、再生位置、業務上の再開判断は Feature が所有する。JibunKit は native object を共通の一個へ置換せず、要求の共存判定、明示切替、世代付き lease、OS event 配送、停止完了後の再構成だけを担う。

`AVAudioSession.sharedInstance()` はプロセスで一つなので `@MainActor MiniAppAudioSessionCoordinator` が唯一 `setCategory` / `setActive` と interruption / route-change observation を所有する。各 Feature の player / recorder と `MPNowPlayingSession` はその Feature の `@MainActor` owner が生成・破棄する。SDK object や通知を別 actor へ渡さず、公開 snapshot/event だけを `Sendable` value に変換する。Swift 6 の厳密 concurrency 下で MediaPlayer handler closure の isolation が安全に `MainActor` へ hop できるかはこの Windows 上でコンパイル未確認であり、実装時に `@Sendable` annotation と SDK overlay を確認する。

## 公開 Swift API 候補

以下は最小候補であり、名前は共通契約確定時に親が固定する。`AVFAudio` 型をそのまま profile に残し、未知の category/mode/options を業務 enum に閉じ込めない。

```swift
public struct MiniAppAudioProfile: Hashable, @unchecked Sendable {
    public let category: AVAudioSession.Category
    public let mode: AVAudioSession.Mode
    public let policy: AVAudioSession.RouteSharingPolicy
    public let options: AVAudioSession.CategoryOptions
}

public struct MiniAppAudioRequest: Sendable {
    public let acceptableProfiles: [MiniAppAudioProfile] // 優先順、空は禁止
    public let purpose: String                           // 競合 UI / log 用
    public let resumeAfterInterruption: Bool             // eligibility のみ
}

public enum MiniAppAudioConflictResolution: Sendable {
    case keepCurrent
    case replaceOwners(Set<MiniAppID>)
}

public enum MiniAppAudioEvent: Sendable, Equatable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reasonRawValue: UInt)
    case configurationChanged
    case mediaServicesReset
}

@MainActor
public final class MiniAppAudioSessionCoordinator {
    public struct Lease: Hashable, Sendable { /* owner + generation + token */ }
    public struct Conflict: Error, Sendable {
        public let requester: MiniAppID
        public let incumbentOwners: Set<MiniAppID>
        public let requestedProfiles: [MiniAppAudioProfile]
        public let reason: String
    }

    public func acquire(
        owner: MiniAppID,
        request: MiniAppAudioRequest,
        stop: @escaping @MainActor @Sendable () async throws -> Void,
        receive: @escaping @MainActor @Sendable (MiniAppAudioEvent) -> Void
    ) async throws -> Lease

    public func resolve(
        _ conflict: Conflict,
        as decision: MiniAppAudioConflictResolution
    ) async throws -> Lease

    public func release(_ lease: Lease) async
}

@MainActor
public final class MiniAppNowPlayingOwner {
    public init(id: MiniAppID, players: [AVPlayer])
    public var session: MPNowPlayingSession { get }
    public func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping @MainActor (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) throws
    public func requestActivation() async -> Bool
    public func invalidate() async
}
```

`MiniAppAudioProfile` の `@unchecked Sendable` は暫定案である。現在の Apple documentation は `AVAudioSession.Category` 等の完全な Swift 6 Sendable 宣言を一覧表示しないため、対象 Xcode SDK で適合を確認し、可能なら unchecked を除く。互換性は全 active request の `acceptableProfiles` に同一 profile が存在することだけで判定する。例えば playback Feature が `.playback/.spokenAudio` と `.playAndRecord/.spokenAudio` の双方を明示すれば後者を許す撮影録音と共存できる。JibunKit が `.playback` を勝手に `.playAndRecord` へ昇格したり options を和集合にしたりしない。

共通 profile がなければ `acquire` は副作用なく `Conflict` を返す（実装では conflict 自体に非公開 token と request snapshot を持たせ、改変・再利用を拒否する）。UI/業務 owner が `keepCurrent` または対象 owner を明示した `replaceOwners` を選ぶ。後者は各 owner の `stop` を呼び、全 callback が返るまで待ち、lease を失効させてから再構成・activate する。対象外 owner、非初期 profile、世代は保持する。停止失敗を握り潰して新構成へ進まず、取消時も incumbent を維持する。複数要求を常に排他にする API や、録音優先などの固定業務規則は置かない。

## 状態と順序

Coordinator は `inactive → configuring → active(profile, leases)`、追加互換要求では `active → active`、非互換要求では `active → conflicted(snapshot)` と遷移する。明示切替は `conflicted → stopping(owners) → configuring → active`、全 lease 解放は producer 停止済みを確認して `deactivating → inactive`。設定/activate 失敗は元 owner がまだ動作可能なら元 profile を復元し、できなければ `inactive + failure` として全関係 owner に通知する。新 requester だけの取消・permission denial・構成失敗で他 owner を停止しない。

Feature 停止順は、(1) 新規 command/操作受付を閉じる、(2) user intent generation を進めて自動再開資格を無効化、(3) player を pause/recorder を stop し native completion または確定状態を待つ、(4) Now Playing target token を登録した同じ command から個別に remove、metadata を消し session/player を解放、(5) audio lease を release、である。`setActive(false, .notifyOthersOnDeactivation)` は最後の lease の producer 停止後だけ行う。Apple は稼働中 audio object の deactivate が object を止め、`isBusy` を返し得るとしているため、deactivate を停止手段にはしない。

Interruption begin は全 active lease に配送して各 producer を停止/一時停止させるが lease は保存する。end の `shouldResume` は許可ではなくヒントであり、次の全条件を満たす owner だけが再開候補となる: begin 時に実行中、request が再開可、同じ lease generation、Feature lifetime が running、管理上 admission 可、ユーザー停止・remote pause・route unplug・競合切替・停止要求がその後にない。再開前に coordinator が profile を再適用し activate する。begin に対応する end が来ない場合もあるので foreground や明示 Play は現状態から再評価する。Siri/remote pause は user-stop generation を進め、遅延した end で誤再開しない。

Route change は全 owner へ理由付き配送する。`.oldDeviceUnavailable` では再生 Feature は pause、録音 Feature は stop 完了を選べるが、coordinator は一律停止を強制しない。他理由は再照会した route/sample rate等を Feature が評価する。media-services reset は古い native generation を無効化し、Feature に再構築を要求する。古い通知、stop completion、remote handler は token/generation 不一致なら無視する。

## Now Playing 所有

各再生 Feature は一つ以上の `AVPlayer` と、それを束ねる一つの `MPNowPlayingSession` を同じ `@MainActor MiniAppNowPlayingOwner` に保持する。Apple の session 固有 `nowPlayingInfoCenter` と `remoteCommandCenter` を使い、手動 metadata の場合は `automaticallyPublishesNowPlayingInfo = false` とする。`addTarget(handler:)` が返す opaque token を command ごとに保存し、`removeTarget(token)` だけを呼ぶ。`removeTarget(nil)`、shared command center の全消去、他 owner の metadata 更新は禁止する。

`becomeActiveIfPossible()` の Bool と `isActive` はOS判断の観測値で、排他 lease とみなさない。既存実機相当 fixture では二つの session が同時に `isActive == true` となったため、JibunKit は Now Playing の単一 owner を仮定しない。remote handler は自身の generation と user intent を検査し、無効なら `.noSuchContent` または `.commandFailed` を返す。`invalidate()` は target 除去と metadata 解放の完了を待つが、別 Feature の session/target/player に触れない。

## 既存基盤と撮影レーンとの接点

- `MiniAppFeatureLifetime.configure` で coordinator lease、Now Playing owner、native producer をその runtime generation に接続し、`runtime.onShutdownAsync` から上記停止順を await する。画面非選択だけでは停止しない。
- `MiniAppSceneActivity` は UI 可視性と background 方針の入力に過ぎず、ユーザーの play/record intent を生成しない。`MiniAppPresentationOwner` は録音許可説明や競合選択 UI の dismissal 完了だけを所有する。
- microphone は `MiniAppPermissionDeclaration(id: "microphone", ...)` による Feature 同意と、app-wide の `AVAudioApplication.requestRecordPermission()` / `NSMicrophoneUsageDescription` の両方を要求する。拒否は requester のみ失敗させる。iOS 17 未満を支える場合の deprecated `AVAudioSession.requestRecordPermission` fallback は deployment target 決定後に条件化する。
- 撮影担当は動画+音声開始前に camera とは別に microphone 同意/OS許可を満たし、本 coordinator へ `.playAndRecord` 等の受入 profile を要求する。無音撮影は audio lease を取らない。競合時に camera session を先に開始せず、切替承認後に audio lease を得てから `AVCaptureSession` の audio input/start を行う。停止 closure は `AVCaptureSession.stopRunning()` と file output の録画終了 callback を撮影 owner 側で待つ。camera の取消だけで他 Feature の audio leaseを解放しない一方、その撮影 owner 自身の microphone lease は解放する。

## 実 Feature 例

1. Podcast Feature は `.playback/.spokenAudio` を第一候補、録音との同居を製品が許す場合だけ `.playAndRecord/.spokenAudio` を第二候補にして `AVPlayer` と session 固有 play/pause command を所有する。ヘッドホン抜去またはユーザー pause 後は interruption end でも再開しない。停止時は pause 完了、target 除去、metadata 解放後に lease を返す。
2. Voice Memo Feature（または音声付き撮影 Feature）は microphone 同意とOS許可後、`.playAndRecord/.measurement` など実際に受け入れる profile を提示する。Podcast と共通候補がなければ理由と incumbent を表示し、ユーザーが切替を選んだ時だけ Podcast の停止完了後に recorder/capture を開始する。録音失敗・取消は自身だけを片付け、無関係な owner とその非初期状態を保持する。

## 検証

自動試験は fake session driver / notification source / producer を注入し、(a) profile 積集合と優先順、(b) 非互換 acquire の無副作用と明示切替、(c) player/recorder停止完了前に再構成しない、(d) requester の取消・許可拒否・activate失敗で他owner保持、(e) lease/notification/remote callback の旧世代拒否、(f) interruption hint + user stop による誤再開防止、(g) route抜去、media reset、解放順、最後のleaseだけdeactivate、(h) Feature B のmetadata/target/profile/世代がA停止後も非初期値のまま、を検査する。加えて通常の Podcast と Voice Memo/音声付き撮影を generated host に接続し、直接 handler を呼ぶ試験と native object 境界の simulator 試験を分ける。CI はこの提案では実行しない。

必要最小限の実機確認は一まとまりで、(1) 実再生と実録音、明示切替および片側取消、(2) 通話等のOS interruption begin/endで再開適格とユーザー停止後の非再開、(3) 有線/Bluetooth代表一経路の切断でpause/stopとUI反映、(4) background entitlement を持つ再生の背景継続、(5) Lock Screen/Control Centerまたは接続アクセサリから session 固有 play/pause が正しいFeatureへ届き、停止後は届かないこと、を端末ログ・画面状態・producer進行値で観測する。simulator で公開 SpringBoard control が取得不能だった既存結果は remote command 配送成功の証拠にしない。特殊 multi-route、任意 engine の同時共存、全Bluetooth機器の総当たりはP2-1範囲外である。

## 親が確定する接点と確認済み一次資料

親に必要なのは、(1) coordinator の host 注入場所と optional `MiniAppDefinition` 接点、(2) conflict を提示・決定する callback/UI owner（自動優先規則ではない）、(3) runtime shutdown へ async producer-stop を登録する既存APIで十分か、(4) deployment target と iOS 17 permission fallback、(5)撮影 lane と共有する profile/lease 型、(6) background audio entitlement / Info.plist 集約、である。撮影側には「音声付き開始/停止completion」と「camera-only cancellationをaudio全体停止にしないowner token」を要求する。

2026-09-16 に Apple 一次資料で次を確認した: `AVAudioSession` は singleton で、`setCategory(_:mode:policy:options:)`、`setActive(_:options:)`、`interruptionNotification`、route change notification を持つこと、稼働 object の deactivate の注意、interruption の should-resume がヒントであること、old-device-unavailable 時の media pause 指針、`AVAudioApplication.requestRecordPermission()` と `NSMicrophoneUsageDescription`、`MPNowPlayingSession` の players / session固有 info center / command center / activation API、`MPRemoteCommand.addTarget(handler:) -> Any` と同tokenによる `removeTarget(_:)` である。

- [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession)
- [setCategory(_:mode:policy:options:)](https://developer.apple.com/documentation/avfaudio/avaudiosession/setcategory(_:mode:policy:options:)) / [setActive(_:options:)](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive(_:options:))
- [Handling interruptions](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html) / [route changes](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioHardwareRouteChanges/HandlingAudioHardwareRouteChanges.html)
- [AVAudioApplication.requestRecordPermission](https://developer.apple.com/documentation/avfaudio/avaudioapplication/requestrecordpermission(completionhandler:))
- [MPNowPlayingSession](https://developer.apple.com/documentation/mediaplayer/mpnowplayingsession) / [becomeActiveIfPossible](https://developer.apple.com/documentation/mediaplayer/mpnowplayingsession/becomeactiveifpossible(completion:))
- [MPRemoteCommand.addTarget(handler:)](https://developer.apple.com/documentation/mediaplayer/mpremotecommand/addtarget(handler:))

Apple documentation の表示で確認できた宣言だけを上記「確認済み」とした。`MPNowPlayingSession` / handler の MainActor annotation、`AVAudioSession` profile constituent の Sendable 適合、通知 AsyncSequence overlay、各APIの厳密な availability は対象 Xcode SDK 宣言をまだ確認できていないため、実装前のコンパイル調査事項である。
