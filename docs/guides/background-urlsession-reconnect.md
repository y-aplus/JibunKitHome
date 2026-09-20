# Background URLSession reconnection

## Current integration contract

Background URLSession work outlives both the visible screen and `MiniAppRuntime`. Give each feature a stable profile identifier, register its factory from `MiniAppDefinition.onHostLaunch`, and retain the process-level connection until the system finishes reconnecting events. Never register from `onAppear`.

The delegate must call the supplied completion exactly once after `urlSessionDidFinishEvents`, while the coordinator owns admission, duplicate reconnect rejection, and shutdown ordering. Treat identifiers and callbacks from another owner or generation as invalid. Build and fixture evidence confirms composition; real background relaunch behavior remains a device-level verification item.

Use a stable nonempty profile such as an account ID. `registerAtHostLaunch` rejects duplicate feature/profile factories instead of overwriting them. The application delegate forwards `handleEventsForBackgroundURLSession` to the registry, which builds the feature delegate without a screen and gives it a `MiniAppBackgroundURLSessionEvents` token owning the host completion.

When callbacks overlap, retain every host completion and wait for the delegate's `finish()` before invoking any of them. Cancellation does not complete early; it keeps the token until the delegate finishes. Because `finish()` invokes the host synchronously and may reenter with a warm callback, first set the delegate's property to `nil`, then call `finish()` on the extracted old token. Reversing this order lets an old callback erase the newly connected token.

## Japanese source notes and historical evidence

background URLSessionは通常画面や`MiniAppRuntime`の寿命とは別にOSから再接続を
要求されます。Featureは安定したprofile名を決め、host起動時にfactoryを登録して
ください。`MiniAppDefinition`の`onHostLaunch`から下記の`registerAtHostLaunch`を呼び、connectionをprocessの必要な寿命まで保持します。画面の`onAppear`から登録してはいけません。[host起動hookの検証](../verification/2026-09-11-host-launch-hook.md)。

```swift
final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    @MainActor var backgroundEvents: MiniAppBackgroundURLSessionEvents?

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let finishedEvents = backgroundEvents
            backgroundEvents = nil
            finishedEvents?.finish()
        }
    }
}

@MainActor
final class DownloadConnection {
    private var registration: MiniAppBackgroundURLSessionRegistration?
    private var session: URLSession?
    private let delegate = DownloadDelegate()

    func registerAtHostLaunch(context: MiniAppContext, profile: String) throws {
        registration = try MiniAppBackgroundURLSessionReconnectRegistry.shared.register(
            context: context,
            profile: profile
        ) { [weak self] identifier, events in
            guard let self else { throw ConnectionError.released }
            delegate.backgroundEvents = events
            if let session {
                precondition(session.configuration.identifier == identifier)
                return
            }
            let configuration = URLSessionConfiguration.background(
                withIdentifier: identifier
            )
            session = URLSession(
                configuration: configuration,
                delegate: delegate,
                delegateQueue: nil
            )
        }
    }
}
```

`profile`はアカウント等を識別する安定した非空文字列です。同じFeature/profileから
同じidentifierが生成され、別Featureまたは別profileとは衝突しません。作成済みの
background sessionに使ったprofileをアプリ更新のたびに変えないでください。

hostの`UIApplicationDelegate`はOSの
`handleEventsForBackgroundURLSession`をregistryへ渡します。registryは対応factoryを
画面なしで呼び、host completionを`MiniAppBackgroundURLSessionEvents`が所有します。
Featureの既存delegateはdownload/data/authentication等を従来どおり処理し、最後の
`urlSessionDidFinishEvents(forBackgroundURLSession:)`から`finish()`を一度転送します。
completionをsession生成直後に呼んではいけません。

同じidentifierへの重複host callbackはfactoryを再実行せず、処理中のpending batchへ
completionを追加します。delegateの`finish()`までどのcompletionも呼ばず、その時点で
各completionを一回ずつ解放します。完了後は同じidentifierの次のOS callbackを受け
付けます。上の例はprocess再生成後だけsessionを作成し、同じprocessのwarm callback
では既存session/delegateを再利用してevents tokenだけを接続します。

registrationの取消はfuture factory登録だけを外します。進行中のpending OS eventは
delegateの`finish()`まで保持し、早期にcompletionを呼びません。取消後に同じ
Feature/profileを再登録しても、古いregistrationの遅延cancel/deinitが新しいfactoryを
削除しません。取消後・再登録前に同じsessionの後着host callbackが届いた場合も、既存
pending batchへ合流してdelegateのfinishまで待ちます。Feature固有の転送取消はFeatureがnative task/sessionへ行い、この
registryを全Feature共通の取消スイッチとして使わないでください。

`finish()`はhost completionを同期的に呼ぶため、そのcompletionから次のwarm callback
接続が再入する可能性があります。delegate propertyを先に`nil`へ戻し、取り出した古い
tokenへ`finish()`を呼ぶ順序を維持してください。逆順にすると、再入で接続した新tokenを
古いcallbackが`nil`で上書きできます。

この基盤はOSがbackground転送を実行する時刻、強制終了後の継続、ネットワーク条件、
再起動配送を保証しません。provider/unit試験とiOS buildはowner routingとnative API
接続の検証であり、実際のOS転送・cold launch配送の実機証拠ではありません。

2026-09-19、診断source `4a1340a` ではこれらの自動試験と別に、実機で診断終了後の別processの
OS callback→owner再接続→同run/taskの10bytes保存→host completion返却を確認しました。
永続証拠はrun `78450873`、task 1。起動契機は未判定で、OSによる自動起動時刻の証明ではありません。
詳細は[実機記録](../verification/2026-09-19-background-http-device.md)。
