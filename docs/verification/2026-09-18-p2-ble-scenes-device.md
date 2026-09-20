# P2-S 実機確認の準備

2026-09-18追補: BLEの通常通信と両Feature/片側停止・再接続はfe1a6e5で実機確認済み。[一括結果](2026-09-18-p2-combined-device.md)を参照。iPadはsideload環境準備をユーザーが見送ったため、実機未確認を保持して待機対象から外す。以下は未実施のiPad手順と当初の検証範囲。通常公開版は0.8.3でP2-S全体は未出荷。

## 自動試験との分担

- 自動: 古いlease/世代の拒否、停止と再接続の競合、登録失敗の巻戻し、片側停止と他方保持、scene資源の解放順、復元停止/回復失敗、実iPad Simulatorでのwindow生成・配送・破棄。
- 実機: BLE電波とOS許可、採用機器での通常read/write/subscribe、OS復元、iPadの実window操作とSceneStorage保持。
- fakeの成功を実無線やOSのcold復元へ読み替えない。OSが破棄したwindowを新規作成する操作は、同じsessionの復元ではない。

## iPadの代表操作（候補合格後）

1. Scene Aを開きincrementで3にする。一覧へ戻り「新しいウインドウ」で二つ目を開き、Scene Bを7にする。二windowでそれぞれ3と7が見えることを確認する。
2. 一方だけを加算・別Featureへ切替し、他方の表示・値が変わらないことを確認する。一方を閉じても残ったwindowが操作できることを確認する。
3. OSによる既存sessionの再接続時に保持される値を確認する。新規windowは初期値でよく、破棄済みsessionの自動復元や任意のView状態保存を要求しない。

指定scene配送と旧generation拒否は自動試験の担当。ユーザーへIDの転記やrace操作の反復は要求しない。Simulatorで確認できなかったOS動作がある場合だけ、上記を補足する。

## BLEは機器条件を先に確定する

必要なのは、scanに応答しservice/characteristicとread/write/notifyの性質が分かる制御可能なBLE peripheral。iBeacon送信だけではGATT接続の検証にならない。Android/iPadがあることだけで、その役割を満たすとは判断しない。

診断画面へservice/characteristic UUIDと送信hexの入力、discovery候補選択、read/write/notify結果表示を追加した。復元通知時には現在のleaseに属する接続ticketを取得して継続操作する。これらは最初のCI対象c35afe7後の追加で、b2f9a04/35295505063の共有24件・native13件・診断IPAで自動検証済み。実無線とOS復元は未確認。既定値180D/2A37は機器の仕様に合わせて変更する。Heart Rate Measurementに任意writeが可能とは限らず、機器の仕様と一致する診断条件を用意するまでは、writeエラーをJibunKit不具合とも合格とも判定しない。

その後、通常通信と片側停止/B継続を一続きで確認し、許可/電源変更・背景復帰・OSによるstate restorationのうち自動試験で代替できない代表操作を追加する。強制終了後にOSが再起動しないことをアプリの復元不良と即断しない。署名条件、OS制約、JibunKit未実装を別々に記録する。

重複service UUIDのinstance選択は現在のUUID-only adapterの制約として残る。これはOS制約ではない。既存adapterがprivateに保持するCBServiceへ利用者が直接アクセスできるとは案内しない。
