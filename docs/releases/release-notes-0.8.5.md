# JibunKit 0.8.5 — scene選択の復元

公開VERSIONは0.8.5/build15、PREVIOUSは0.8.4/build14。2026-09-19公開。1.0.0の完成判定ではありません。

## 変更

windowごとの選択Featureを保存し、OSが保存したsessionを再接続したときに復元します。保存先が無効・未登録なら消去し、後日同じFeatureを導入しても勝手に開かないようにします。任意のFeature画面階層やメモリ状態を自動保存するものではありません。

BLEは新processでのOS state restorationと同一世代へのNotify配送を実機確認しました。診断では現在processの結果と過去processの完全な復元証拠を分けて表示します。通常IPAは引き続きCounter/Reminder・Widget・Shareのみで、診断Featureを含めません。

## 証拠と未確認

- 99632e3 / CI35355170934: native82件・OS UI5件成功。二windowの異なる所有者・値・元session IDの復元と片側破棄後の他方保持、無効保存先の消去、Simulator背景位置callback、英語Widget・代表camera許可文言を確認。
- 59f7081の実機BLEログ: 新processのOS復元callbackから同一owner/generationのNotify2bytesまで確認。OSがprocessを起動した契機は未判定で、自動起動時刻や遅延を保証しません。
- feab170 / CI35357260854: 0.8.5通常版build/IPA、共有443件（既存skip2）・Module11件と保存先復元/cold URL優先の限定UIが成功。2026-09-19に通常IPA上書き後のCounter/Reminder保持とCounterの前景復帰後の表示・操作を実機確認。cold復元の実機再試験ではありません。

物理iPad、実境界/iBeacon電波、CloudKit/APNs実通信、ARの実OS interruption復帰などは未確認です。継続処理code1の追加追究は停止しています。Files自動UIの失敗は独立したUIKit/SwiftUIでも再現しており、同じ操作の反復はしません。過去の実機成功と今回候補の証拠を区別します。

候補source: `feab1702777c4f49cde4145faab93fe9dbfb4747`、通常CI:35357260854。IPA:4,747,914 bytes、SHA-256:`f1d1cb0ff56721f5add340a629fd4f86536a28b986ebada08a5394c5767dff42`。3bundleの0.8.5/15・App Group・署名検査・全entry CRC・診断ownerの非混入を確認。旧release/tag/assetは差し替えません。
