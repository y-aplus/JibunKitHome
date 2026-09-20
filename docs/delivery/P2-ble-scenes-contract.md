# P2-S: BLEと通常複数window

> 履歴注記: 本文はP2-S開始時の実装契約である。通常BLE/scene採用範囲の現在状態と後段の実機証拠は[plan.json](plan.json)と[status](../status.md)を優先する。

2026-09-18開始。P2-9/D24とP2-11/D01,D04。P2-Iの共有/通常CI35249566535とnative12件CI35253192466を継承する。実APNs/CloudKit通信、P2-Bの背景/cold/電波確認は未完のまま別管理し、この作業で完了扱いしない。ユーザー睡眠中は実機操作を要求しない。

## 所有と契約

JibunKit projectのSol low別スレッド2本。ワーカーはCIを実行せず、担当パスの実装・試験・ガイドをまとめて提出する。親がレビューして通常/sharedと両領域のnative検証を一つの境界として固定する。初回予算3run、遅くとも3失敗ごとに原因切り分け。準備/upload込み25分見込みを事前に記録し、完了通知のみで再開する。元のC:/Dev/JibunKitのdirty files/ignored Zaikoは変更しない。mainへ未検証統合しない。

既存MiniAppDefinition/ID/Context、FeatureLifetime/Runtime、管理/外部受付・選択復元・scene routerと宣言合成を再利用する。native APIを不要に狭いfacadeへ閉じ込めず、所有/停止/調停の不足を補う。通常A/B同時動作、片側停止・削除・失敗・復帰で他方の非初期状態を保持する。fake成功、Simulator OS操作、実機/電波を区別する。

## BLE担当

所有: Sources/JibunKitCore/Bluetooth/、Tests/JibunKitCoreTests/Bluetooth/、Tests/P2Bluetooth/、docs/guides/bluetooth-ownership.md、docs/delivery/P2-bluetooth-submission.md。

CoreBluetooth centralの通常scan/connect/disconnect、電源/許可、service/characteristic discovery、read/write/subscribeを扱う。owner別manager/restore identifierとperipheral/delegate lifetimeを設計し、停止・遅着・重複・再接続を区別する。同じ周辺機器に複数Featureが関わる場合も所有契約を明示し、他ownerの接続を誤って取消さない。background-centralのnative state restorationは同期host launch hookへ接続し、無効ownerを復活させない。標準CB型の利用余地を残す。汎用BLEプロトコル/特殊機器網羅/peripheral role一般化はしない。

Tests/P2Bluetooth/P2BluetoothProbe.swiftで通常二Feature定義を公開、P2BluetoothNativeTests.swiftで同じ定義/管理を通す。Simulatorに電波能力がないことを明示し、adapter compileとfake callbackを実無線受信と呼ばない。使用説明/背景mode/復元接続の必要宣言は提出に示す。host/manifest/workflowは親が所有。

## scene担当

所有: Sources/JibunKitCore/WindowScenes/、Tests/JibunKitCoreTests/WindowScenes/、Tests/P2Scenes/、docs/guides/window-scene-ownership.md、docs/delivery/P2-scenes-submission.md。既存scene routerを変える必要があれば親へ変更対象と理由を一度まとめて通知する。

通常iPad二windowの生成・独立navigation/Feature状態・指定scene配送・破棄・復帰を扱う。OS session identityと一時connection generationを分け、古いscene参照へ遅着させない。windowを閉じても別windowの同一Featureや別Featureを勝手に止めない。Feature global lifetimeとscene単位資源を区別する。既存SceneStorage/navigationを再利用し、任意Viewの自動serializationや全FeatureのCodable強制はしない。

Tests/P2Scenes/P2ScenesProbe.swiftとP2ScenesNativeTests.swiftに二scene/ownerの通常接続試験とiPad OS操作用診断を用意する。実二windowのOS検証はiPad Simulator/実機を区別し、二つのSwiftオブジェクトだけでOS成功としない。必要なhost Scene/manifest接続を具体的に提出する。Sources/JibunKit、Project.swift、workflowは親が所有。

## 提出とレビュー

Swift6 actor isolation、escaping closure capture、XCTest helper隔離を提出前に一括確認する。前境界のコンパイル修正を繰り返さない。SwiftがないWindowsでは実行済みと書かず、API署名はApple一次資料で照合する。管理停止→native取消/join→削除/復元の順序を試験に含める。提出は実装commit、未実行一覧、接続手順と条件、残件を一度通知する。親はsource確定後に同一SHAの検証を組む。

## 開始状況

基点afb8f50でJibunKit所属のSol low別スレッド2本を起動。親は`codex/p2-ble-scenes`へ分岐。既存native workflowの実選択コードにiPad必須のsurface条件を追加し、既存major/runtime選択3件とiPad必須/利用不可拒否2件が成功。新surface自体の登録・host生成は担当API提出後にまとめて接続するため、CIは未投入。

P2-Iの失敗を踏まえ、Core/診断app/native testのSwift6隔離を提出前レビュー対象へ明記した。実OS window生成にはmanifest/host接続とiPadが必要であり、二つのnavigationオブジェクトの成功で代用しない。BLEのSimulator制限もnative生成と実無線を区別する。

sceneは初回ef0f20aから8100cfa、96647adの修正まで統合。再接続cleanup await中の再入、無効ownerの受付拒否、既に切断されたsceneの資源解放待ちを補強した。親が実WindowGroup rootへOS session接続・独立navigation配送を追加し、管理停止と選択復元へscene資源の取消/joinを接続した。実iPad Simulatorの二window生成・指定配送・破棄、および復元停止失敗/回復失敗時の受付維持を試験対象にする。Swift/Xcode未実行であり合格扱いしない。

BLEは初回f8e8582と修正cac8201を統合。binary広告情報、write backpressure、復元受付、lease/世代検査を追加した。親レビューで、取消join中の再connect/新lease受付、閉じたruntimeへの登録失敗、同一UUID service列によるtrapの残件をまとめて返却した。3d0f1cf/28d637fで停止barrierをawait前に公開し、再接続/停止/新leaseの三者競合試験、閉じたruntime登録の巻戻し、重複UUID拒否を追加した。Simulator試験は同じFeatureへfake managerを注入し、診断実機のnative adapterと分離。親レビューを終え、227ab3bを最初のCI対象sourceとする。

親のhost生成/実workflow Simulator選択/既存media・background・identity生成と検証器のローカル試験は合計19件成功。P2-S CIは0回。通常/sharedとiPad nativeを同じsourceで実行する。通常UIは今回変更した選択復元/他Feature保持のFiles往復を選択。詳細は2026-09-18-p2-ble-scenes-evidence.jsonへ記録する。既存P2-Iの所要18分12秒/13分27秒を見積りの根拠にし、P2-S追加試験を含む上限見込み25分を確認してから投入する。
