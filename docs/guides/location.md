# Using location from a feature

## Current integration contract

A feature owns its typed location requirement and business interpretation; the shared location coordinator owns authorization requests, native manager lifetime, capacity, and callback routing. Bind every request and monitoring registration to an owner and generation, and reject callbacks after stop or removal.

Register required host-launch restoration before UI appears. Background updates, geofences, and iBeacon monitoring also require host capabilities and usage descriptions. Run 35371803883 observed real OS background callbacks plus cold geofence enter/exit delivery. That evidence is distinct from still-unverified physical movement, radio, accuracy, authorization-transition, reboot, and power-behavior conditions.

Declare the stable `location` permission, construct `MiniAppLocationService` with the feature owner, and have its consent closure read that owner's consent. Connect it from `MiniAppFeatureLifetime`, expose `service.externalAccess`, and call `reconnectPersistedMonitoring()` synchronously from `onHostLaunch` for region-owning features. Management must call `unregisterAllOwned()` on removal. Wire `onConsentChange` to `featureConsentDidChange()`; denial persists even if cleanup fails and revokes only that owner's updates and regions. Feature consent is checked before any OS prompt or native registration and remains distinct from app-wide OS authorization.

`startUpdates(_:)` creates a generation-scoped manager using the feature's requested accuracy, distance filter, activity type, auto-pause, and background indicator. Stop with the returned generation and drop late callbacks. Enable `UIBackgroundModes = location` before setting background updates. When In Use can continue an already-running session while the app runs; relaunch for region/significant-change events requires Always authorization. Native `CLLocation` delivery is available through `receiveCoreLocations` after the same owner/generation checks.

`register(localID:region:)` persists an owner-qualified identifier before monitoring. Reject excessive radii with the requested and maximum values, test geofence and beacon availability separately, and reject a beacon minor without a major. Count JibunKit reservations plus unknown host `monitoredRegions` against the app-wide limit of 20; return `capacityExceeded` without evicting anything. Release a reservation on registration failure. Cancellation also works before `didStartMonitoringFor`; a late success after cancellation is stopped immediately.

On relaunch, validate persisted metadata and re-register only missing regions after management, consent, authorization, and capacity checks. Corruption, duplicate owner/local IDs, or invalid coordinates fail closed and prevent destructive writes for that process. Never restart continuous updates automatically. Unknown identifiers are not delivered across owners; only manager-wide errors without an identifier may be broadcast. Restore closes ordinary and cold delivery for that owner, and a concurrent management disable prevents resume from reopening it.

## Japanese source notes and historical evidence

JibunKitの位置APIは、Featureごとの同意・owner・世代をCore Locationのapp共有状態に重ねる。Featureは用途に応じた`desiredAccuracy`、`distanceFilter`、`activityType`、自動pause、背景表示を選び、JibunKitは一律の精度へ書き換えない。

## 接続

1. `MiniAppPermissionDeclaration(id: "location", ...)`をFeature定義へ加える。
2. `MiniAppLocationService`をFeatureの`MiniAppID`で作り、同意closureでは`MiniAppConsentStore`の同owner・`location`を確認する。
3. `MiniAppFeatureLifetime`のconfigureから`service.connect(to:)`を呼ぶ。接続tokenはruntime世代に結び付き、停止時はその世代だけが連続更新とcallback配送を閉じる。閉じたruntimeへの接続はrollbackされ、接続前／停止後の操作は`.stopped`になる。
4. `MiniAppDefinition.externalAccess`へ`service.externalAccess`を渡す。これにより管理状態がcold launch前に適用され、disableは当該ownerの仕事だけを停止・解除する。
5. Regionを使うFeatureは`onHostLaunch`から`try service.reconnectPersistedMonitoring()`を同期的に呼ぶ。これは管理 admissionと永続Feature同意を両方確認し、画面表示前からowner別cold callbackを受け付ける。永続metadataの読込失敗はFeatureの状態表示へ保存し、host全体を終了させない。`onUnregister`では管理用`service.unregisterAllOwned()`を呼ぶ。

Feature同意がない場合、OS許可dialogもnative登録も開始しない。OS許可はapp共有だが、Feature同意と登録解除はowner別である。
`MiniAppDefinition.onConsentChange`へ対象permissionの変更処理を接続する。標準管理画面は`definition.setConsent(_:permissionID:in:)`で保存後にこのhookを呼び、cleanup失敗を表示する。拒否は失敗時も保存されたままである。hookで`service.featureConsentDidChange()`を呼ぶか、渡された拒否を使って同ownerをrevokeする。Viewの表示や`onChange`だけに依存しない。このownerの連続更新と永続Regionだけを停止・解除し、app共有OS許可や他ownerは変更しない。

## 前景・背景の標準更新

`startUpdates(_:)`は設定を保持した専用`CLLocationManager`をgenerationごとに作る。返されたgenerationを`stopUpdates(generation:)`へ渡す。停止済み世代の遅着callbackは配送しない。他ownerは別managerなので、一方の停止で他方を止めない。通常のvalue配送は高度、速度、course、各精度、source情報も保持する。iOS FeatureがSDK固有値を必要とする場合は`receiveCoreLocations`で同じowner/generation検査後の`CLLocation`を受け取れる。

`background: true`にはhost targetのBackground Modes > Location updates（`UIBackgroundModes = location`）が必須である。これなしで`allowsBackgroundLocationUpdates = true`にするとappが終了する。When In Useでも、前景で開始しappが動作中なら背景更新を継続できる。終了後にOSがappを再起動してregion/significant-change系イベントを届ける条件にはAlways許可が必要である。背景利用の説明とindicatorはFeatureの用途に合わせる。

## geofenceとiBeacon

`register(localID:region:)`はowner、local ID、generationを含む衝突しないOS identifierを作り、永続化後に通常の`CLLocationManager.startMonitoring(for:)`へ渡す。geofence半径が端末の`maximumRegionMonitoringDistance`を超える場合は黙って丸めず、要求値と最大値を返す。geofenceとbeaconのavailabilityは別々に確認する。iBeaconのminorだけを指定する入力は拒否する。

Core Locationのregionはapp内全managerで共有され、1 app最大20件である。登録前にJibunKit所有予約と`monitoredRegions`内の未知のhost登録を合わせて数える。満杯なら`capacityExceeded(limit: 20, occupied: ...)`を返し、既存登録を勝手に入れ替えない。登録失敗callbackでは予約を解放する。解除は完全なowner付きidentifierで対象を特定し、他Featureやhostのregionを止めない。

再起動後、OSはRegion自体を保持する。JibunKitは検証済み永続metadataを読み、管理・同意・OS許可済みでOS側に欠けるものだけ、共有20枠を再評価して再登録する。破損、重複owner/local ID、不正座標等を検出したstoreは失敗を可視化し、そのprocessでは破壊的writeを拒否する。連続位置更新は勝手に再開しない。端末再起動後のmonitoringはユーザーが一度端末をunlockした後に有効になる。

`startMonitoring`の完了は非同期である。adapterは要求した`CLRegion`を保持するため、`monitoredRegions`へまだ現れていない間の解除も取り消せる。解除後に`didStartMonitoringFor`が遅着した場合は直ちに同じRegionを停止する。未知identifierの失敗は他ownerへ配送せず、identifierがnilのmanager全体エラーだけを全ownerへ知らせる。

## host設定

- `NSLocationWhenInUseUsageDescription`: 前景または実行中背景の位置用途。
- `NSLocationAlwaysAndWhenInUseUsageDescription`: 終了後のregionイベントによる再起動を必要とする用途。
- `UIBackgroundModes`の`location`: 連続背景更新、およびiBeaconでapp launchを求める診断。
- 起動時: managementを先に生成して`externalAccess.prepare(enabled)`を適用し、registry確定後かつFeature UI表示前の`application(_:didFinishLaunchingWithOptions:)`で各定義の`onHostLaunch`を呼ぶ。
- Feature同意変更時: `onConsentChange`を通し、対象位置serviceの`featureConsentDidChange()`を呼ぶ。

選択復元中はこのownerの通常・cold callback配送を閉じ、復元後も連続更新を自動再開しない。復元中に管理無効化された場合は、復元のresumeだけで再度受付可能にしない。古いserviceやruntimeの終了は新しい同owner接続を止めない。

usage descriptionはFeature同意の代わりではない。管理画面でFeatureを無効化するとlifetime cleanupをjoinし、Feature削除では`onUnregister`を実行してownerのRegionだけを消す。単なる画面非表示で永続Regionを解除しない。

## 実機確認

Simulatorの位置simulationは配送・表示の結線確認にのみ使える。物理的な背景起動、移動によるgeofence進退、再起動後の配送、Bluetooth電波によるiBeacon検出の証拠には実機が必要である。iBeacon試験は別の送信機材（UUID/major/minorが一致）を用意し、region monitoringで進入後に必要ならFeature側でrangingを開始する。rangingを常時背景動作と仮定しない。

参考: [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background), [Requesting authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services), [monitoredRegions](https://developer.apple.com/documentation/corelocation/cllocationmanager/monitoredregions), [Monitoring geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions), [Determining proximity to an iBeacon](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device).
