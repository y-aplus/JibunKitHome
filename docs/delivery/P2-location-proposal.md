# P2-3 位置レーン提出

> 履歴注記: 本文は位置レーンの提出時点を保持する。後段で確認したOS background callback/geofence証拠と残る物理条件は[status](../status.md)と[plan.json](plan.json)を優先する。

基準commitは`57542e66981373d2de3d112aca91ea1aa56c07cf`。Featureが位置用途、精度、成果、業務判断を所有し、JibunKitはFeature同意、owner別登録、共有監視枠、世代配送、停止／再接続の境界を実装した。大量Regionの仮想化や予測入替、独自scheduler、常時beacon rangingは対象外である。

## 実装判断

- `MiniAppLocationService`をFeature ownerの入口にし、同意確認をOS permission requestおよびnative開始より先に行う。OS許可はapp共有、Feature同意はowner単位で分離した。
- runtime接続はtoken付きで、cleanup登録成功後に公開する。閉じたruntimeは接続を残さず、古いruntimeの遅着cleanupは新世代を切断しない。停止後のservice操作は拒否する。
- 連続位置更新はgenerationごとに通常の`CLLocationManager`を一つ使う。Feature固有のaccuracy、distance filter、activity、pause、背景indicatorを保持する。停止・許可喪失・runtime shutdownで当該generationを閉じ、遅着を捨てる。他ownerのmanagerは停止しない。
- geofence/iBeaconはowner、local ID、UUID generationからOS identifierを生成する。OSの`monitoredRegions`がapp内全managerで共有されるため、未知のhost regionも20枠へ計上し、満杯時は既存値を変えず説明可能な`capacityExceeded`を返す。
- metadataを`UserDefaults`へ永続化してからnative登録する。読込時にもowner、座標、半径、beacon階層、owner/local重複を再検証する。破損は可視化し、そのprocessの破壊的writeを拒否する。取消書込失敗は全ownerのmemory/disk状態をrollbackする。
- cold launch hookは`externalAccess.prepare`で適用済みの管理状態と永続Feature同意を確認し、画面なしのcold consumerを先に用意してから、OS側に欠けるRegionだけ20枠を再評価して接続する。連続更新は自動再開しない。
- `startMonitoring`要求Regionをadapterが保持し、登録完了前の取消と遅着`didStartMonitoringFor`を掃除する。未知identifierの失敗はbroadcastせず、nilのmanager全体エラーだけを全ownerへ配送する。
- value sampleはCLLocationの高度、速度、course、各精度、source情報を保持する。さらにiOS限定`receiveCoreLocations`を同じowner/generation境界から提供する。geofence/beacon availabilityを分離し、過大半径は最大値を含む失敗とする。
- Region callbackはAppleの仕様どおりobject identityではなくidentifierで配送する。知らないidentifier、解除済みgeneration、停止済み更新generationは破棄する。

## 実Feature診断

`P2LocationProbe.definitions`は通常の`MiniAppDefinition`を二つ返す。

- `p2-location-tracker`: When In Use／Always要求、設定を変えた前景・背景標準更新、明示停止、更新数と最新sampleを表示。
- `p2-location-regions`: 現在地取得または編集可能な緯度・経度・半径によるgeofence、既知UUID/major/minorの診断iBeacon、再起動後も復元されるowner登録一覧と個別解除、進入／退出／状態／失敗を表示。

両Featureは独立したlifetime、同意、owner、非初期stateを持つ。`P2LocationNativeTests`はdefinitionsの実入口、独立start/stop、host launch hook、実Core Location adapter設定、SDK `CLLocation`出口、pending Region取消、実management disable時のB保持を検査する。

## 合格条件と試験対応

| 合格条件 | 自動試験 |
|---|---|
| Feature拒否時にOS prompt/native仕事を開始しない | `testFeatureConsentPrecedesOSPromptAndNativeWork` |
| 同local IDでも二ownerを分離して配送 | `testTwoOwnersWithSameLocalIDReceiveOnlyTheirRegistration` |
| A解除でBと未知host regionを保持 | `testOwnerUnregisterPreservesOtherOwnerAndUnknownNativeRegion` |
| OS共有20枠を事前説明し既存値を保持 | `testSharedTwentyRegionLimitIncludesUnknownNativeRegistrations` |
| 永続化失敗をrollback | `testFailedPersistenceRollsBackReservationBeforeNativeStart` |
| 停止後の遅着世代を配送しない | `testLateUpdateFromStoppedGenerationIsDropped` |
| cold再接続でRegionのみ復元し連続更新を再開しない | `testPersistedRegionsReconnectWithoutRestartingContinuousUpdates` |
| When In Useで前景開始後の背景継続設定を保持 | `testBackgroundAndForegroundPreserveConfigurationWithWhenInUse` |
| OS許可喪失で全ownerの連続更新を止め、durable Region metadataを保持 | `testAuthorizationRevocationStopsEveryUpdateButKeepsDurableRegions` |
| 非同期monitoring失敗で予約枠を解放 | `testMonitoringFailureReleasesOwnedReservation` |
| Feature同意取消で当該ownerだけ停止・解除 | `testFeatureConsentRevocationStopsAndRemovesOnlyThatOwner` |
| closed runtime rollback、同owner再接続、古いcleanup遅着 | `testClosedRuntimeConnectionRollsBackAndRejectsOperations`, `testLateOldRuntimeCleanupDoesNotDisconnectNewGeneration` |
| store破損の可視化・write拒否、取消失敗rollback/B保持 | `testCorruptStoreIsVisibleAndRefusesDestructiveWrite`, `testFailedOwnerRemovalRollsBackAndSurvivesRestartWithOtherOwner`, `testDecodedRegistrationRevalidatesOwnerAndRegion` |
| 画面前cold配送、disabled/同意取消owner非再開、B保持 | `testColdHookFiltersDisabledOwnerAndDeliversEnabledOwnerBeforeViewConnection`, `testColdServiceDoesNotReconnectWhenFeatureConsentWasRevoked` |
| 未知monitor失敗の隔離、nil全体失敗 | `testUnknownMonitoringFailureIsNotBroadcastButGlobalFailureIs` |
| beacon階層と最大半径を説明可能に拒否 | `testBeaconMinorWithoutMajorAndOversizeRadiusAreExplained` |
| 実Feature二owner、通常lifetime/hook、native adapter、pending取消、management保持 | `P2LocationNativeTests` 6件 |

## Apple一次資料とSDK条件（2026-09-17確認）

- [Handling location updates in the background](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background): Background Modes、背景session、終了時の再生成、未決定許可でlaunch時に開始しない条件。
- [`allowsBackgroundLocationUpdates`](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates): `UIBackgroundModes=location`なしでtrueにするとfatal、前景開始後のWhen In Use背景継続、既定false。
- [Requesting authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services): When In UseとAlwaysの差、終了appをregion等で自動launchするにはAlwaysが必要。
- [`monitoredRegions`](https://developer.apple.com/documentation/corelocation/cllocationmanager/monitoredregions): 全manager共有、identifierが唯一の識別、launch間のOS永続化。
- [Monitoring geographic regions](https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions): appあたり同時20 condition、未起動app launch、再起動後unlock条件。
- [Determining proximity to an iBeacon](https://developer.apple.com/documentation/corelocation/determining-the-proximity-to-an-ibeacon-device): monitoring→rangingの二段階、背景launch設定、実beacon識別値。
- [`CLLocationManagerDelegate`](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate): authorization、位置、Region、失敗callback。manager生成threadのrun loop配送なのでadapterをMainActor所有とした。

実装はiOS 26 package条件だが、Region APIは現SDKでdeprecated表示される通常`CLLocationManager`構成を意図的に保持した。理由は契約が既存のgeofence/iBeacon Regionとcold launch再接続を要求し、`CLMonitor`へ一律移植してiBeacon等の機能を狭めないためである。iOS 26 SDKでの厳密なcompile/deprecation警告はCI側のXcodeで確認が必要。

## 共有変更要求（親が統合時に実施）

担当所有path外は編集していない。次を共有側へ追加する必要がある。

1. 診断host registryを組み立てる箇所で`P2LocationProbe.definitions`を既存definitionsへ追加する。各definitionの`externalAccess`を既存management registrationへそのまま渡す。
2. hostの`application(_:didFinishLaunchingWithOptions:)`でregistry確定後・scene表示前に各定義の`onHostLaunch`を呼ぶ既存公開hookへ接続する。既に全定義hookを呼ぶ構成なら追加呼出し不要。
3. 診断host Info.plistへ`NSLocationWhenInUseUsageDescription`、`NSLocationAlwaysAndWhenInUseUsageDescription`を追加し、Background Modesの`location`を有効にする。
4. `Tests/P2Location/P2LocationProbe.swift`と`P2LocationNativeTests.swift`をiOS native test targetへ追加する。`Package.swift`やProject/workflowは担当境界のため未変更。
5. 親統合で`MiniAppDefinition.onConsentChange`と保存後callbackを追加した。標準管理画面から共通hookを通して対象ownerの位置処理を停止するため、hostに位置Feature名による分岐を追加しない。

親統合では、Swiftの条件付きコンパイルをparameter listから宣言/statement境界へ移し、置換済みserviceの再操作拒否、service解放後のruntime cleanup、読込失敗後のmonitoring callbackによる破壊的write拒否、復元中のcold配送停止を追加。Core4件と共通同意hookのnative1件を追加したが、Swift/iOS実行結果はCI受領まで未検証である。

## 検証結果と未解決条件

Windows環境にはSwift/Xcode/iOS SDKがなく、Core/native testおよび実Feature compileは未実行である。PowerShellで所有path、参照、Git差分の静的確認を行う。親CIで`swift test --filter MiniAppLocationCoordinatorTests`とP2Location native targetのcompile/testが必要である。

実機でのみ検証できる項目は、(a) 許可dialogとSettings変更、(b) Background Modes付き標準更新のbackground/foregroundと停止、(c) app終了／端末再起動・unlock後のRegion配送、(d) 実移動によるgeofence進退、(e) 別送信機材によるiBeacon進入／退出、(f) 20枠付近のOS登録失敗callbackである。Simulator mock位置は物理背景起動や移動の証拠にしない。物理iBeacon送信機材がなければbeacon実測だけ未検証として残し、owner配送と失敗状態は自動試験で確認する。
