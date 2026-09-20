# AndroidをBLE試験用の相手機器にする準備

2026-09-18、Android nRF ConnectとiPhoneの組合せで手動GATT通信を確認した手順。BLE診断版fe1a6e5の[結果](2026-09-18-p2-combined-device.md)と区別して読む。macroは実機で使用しておらず、以下では必要ない。

## Androidの初回設定

1. 「Configure GATT server」の上部選択で新規設定を作る。
2. ADD SERVICE → Custom service。Primary service UUIDは以下。

```text
ad539a02-1289-44dc-bd27-f991c68a1fb9
```

3. service行を展開しADD CHARACTERISTIC。次のUUIDへREAD + WRITE、通常のREAD/WRITE permission（暗号化・認証なし）を設定。

```text
9e0f4195-64b6-4c4a-8ffa-e8dd8f4036d5
```

4. もう一つ追加。次のUUIDへREAD + NOTIFY、通常のREAD permission。CCCD 2902は自動追加される。

```text
0b1ec4d4-1383-4460-b1e2-9ae98653cc1b
```

5. Advertiser → ＋。connectableを有効にし、ADD RECORDで上記service UUIDを追加。Scan responseへComplete Local Nameを追加すると、現在のAndroid機種名などが広告名になる。端末名の変更は必須ではない。
6. 広告を保存してオン。開始エラーの場合はそこで止める。
7. 報告: 広告を開始できたか。

## 接続と読み書き

1. JibunKitの管理でBLE SensorまたはBLE AccessoryのBluetooth利用を許可。画面名をBLE A/Bとは案内しない。
2. 対象Featureの「スキャン開始」→自分のAndroidの機種名→接続済み。接続後はスキャン停止してよい。スキャン候補は停止しても消去されない。
3. 全Service検索→上記Service候補を押す。
4. Characteristic UUID欄をRead/Write UUIDへ変更→指定Characteristic検索→Read。未設定値は空の場合がある。
5. 送信bytes hexへ`0304`→Write with response→Read。
6. 報告: Write結果とRead結果。期待は成功と`03 04`。

Service UUID欄はscan filterではない。名前だけで相手を断定せずserviceを照合する。

## 通知（実機で使用した手動操作）

1. JibunKitのCharacteristic欄をRead/Notify UUIDへ変更→指定Characteristic検索→Subscribe。
2. Androidの接続タブ（今回の表示名はN/A）→SERVER→作成service→Read/Notify characteristicの上向き矢印。
3. Notify/Indicate画面で形式は「Byte array」、New valueに`0506`。Save asは空欄。送信ボタン名は「Send」（SaveやNotifyではない）。
4. 報告: JibunKitのNotify状態とNotify受信値。期待は購読中と`05 06`。

接続タブ・矢印が見つからなければ実際の表示名を確認して止める。画面や選択肢を推測して断定しない。報告も手順番号に含め、ユーザーが対象を指せるようにする。Android画面を操作している間にiPhoneでChatGPTを前景表示してもよいが、JibunKit背景中のcallback実行時刻の証明とは別。

## 確認の範囲

単独read/write、notify、unsubscribe/resubscribe、scan停止後受信、切断/再接続後受信、同一Androidへ両Feature購読、片側無効化後の他方受信を確認。旧候補の複数owner失敗は修正後に再現しなかったが、内部原因を確定する併用時ログは周辺広告で押し出されており未取得。成功の追加反復は求めない。

[任意macro](../../Tests/Fixtures/ble-peripheral/JibunKit-P2S-notify.xml)は公式形式とXML構文だけ検査済みで、実機import/実行は未確認。iBeacon実受信・cold state restorationも別の未確認項目。名前/UUID照合は認証ではなく、一般の心拍計へ試験値を書き込まない。

## Primary references

- [Nordic nRF Connect documentation: Advertiser and Configure GATT Server](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/documentation/README.md)
- [Nordic macro XML grammar: server read/write, set-value, and send-notification](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/documentation/Macros/README.md)
- [Nordic macro XML example using hexadecimal bytes](https://github.com/NordicSemiconductor/Android-nRF-Connect/blob/main/Thingy52%20sample%20macros/macros/Blinky.xml)
- [Android Bluetooth permissions](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)
- [Android BluetoothLeAdvertiser API and 31-byte legacy limit](https://developer.android.com/reference/android/bluetooth/le/BluetoothLeAdvertiser)
- [Android BluetoothAdapter advertising capability check](https://developer.android.com/reference/android/bluetooth/BluetoothAdapter)
