# P2統合候補の実機確認

対象は`p2-combined`生成host、source `c66b624419b23470881a926d197118293d9bc1b2`。CI合格と公開IPAの再取得照合が完了。公開0.8.3を置き換える正式リリースではなく、AR・Action・idleの代表実機結果を受領済みです。残件は以下に区別します。

## 再試験しない既存成果

f6f6c04で実機確認したHTTP転送のbackground host callback→Feature再接続→保存→completion解放は再利用します。OS継続処理のcode1はnative直接比較でも再現したため、ユーザー指示どおり追加追究を停止します。単なるhost起動をcold HTTP復元や位置イベント起因の起動とは扱いません。単体native試験の成功を実無線や実OS配信へ読み替えません。

## 確認のまとまり

| まとまり | 残る実機確認 | 条件 |
| --- | --- | --- |
| iPhone単体 | AR実frame/開始元離脱/停止、ActionのOS入口/入力/取消、代表の用途説明、idle要求と実際の消灯復帰 | AR対応端末。用途説明のためだけに既存全権限を再設定しない |
| iPad | 二windowで別Feature/値を保持、一方の終了で他方を維持 | ユーザーが利用できる時点から。日付だけで利用可能とは判断しない |
| BLE | 自分の制御可能なGATT peripheralとのread/write/notify、片側停止/B維持、背景復帰 | service/characteristic仕様が分かる機器。Heart Rate Measurementへの任意writeで代用しない |
| 位置/iBeacon | 実移動/境界または実beacon受信のうち機器条件が整うもの | 屋内静止やcallback件数だけで背景位置/境界通過を合格にしない |
| CloudKit/APNs | 署名・サービス条件を満たす場合だけ実通信/実OS配信 | entitlementを偽装せず、無料署名での統合smokeと分ける。1.0の判定条件はユーザーへの質問中 |

代表操作は順番に行い、camera/BLE/location/idle/backgroundを同時に動かしたことを暗黙に保証しません。controller/世代/取消race・文字列一致・bundle配置の検査は自動化し、利用者へ精密なタイミング操作や各小変更ごとのIPA入替えを要求しません。まず条件が整ったまとまりだけを読みやすい短い手順で案内します。

## 自動検証と配布

[CI35300688982](https://github.com/y-aplus/JibunKit/actions/runs/35300688982)はc66b624で成功。iPad Simulatorの69 native試験、failure0/skip0。全19 Featureの実host起動登録とエラーなし、外観5件、built Widget翻訳、用途説明en/jaとWidget非混入、Share/Action/Widget署名とIPA検査を確認。setup/upload込み14分37秒。実無線・tracking・OS Action入口を自動検証済みとはしない。

- [診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-combined-check-20260918/JibunKit-P2-combined-check.ipa): c66b624、6,387,415 bytes、SHA-256 `42fafdd0f36e67562941a885136aac242c7cbfd2da7c120e6c7fe7f7235fc2cd`。
- [戻し用通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-combined-check-20260918/JibunKit.ipa): 41c97f1944c184540c6e297b8e6cf2dfbc5ac52d、4,721,656 bytes、SHA-256 `691e163ae10b29161775cb4f38a6f7afd737b21e7911cca9abf38f911be4e710`。CI35298791125の通常Counter/Reminder版。安定版0.8.3そのものではない。

両IPAとも内部版0.8.3/build13。同じアプリへ上書きする。公開URLの無認証GET、SHA一致、全entry CRCを照合済み。ZIP配布は追加しない。

## 最初の確認（iPhoneだけで実施可能）

1. 診断IPAを上書きし、Counter/Reminderの既存値と一覧が開けることを確認。
2. 「ミニアプリの管理」→AR Probe→カメラ→「このアプリでの利用」を許可。その後「AR Probe」→「AR開始」（iOS許可が出れば許可）。framesが増えれば実frame受信。トップへ戻って再入場した後は止まっており、開始・停止し直せることを確認。描画ビューではないためカメラ映像が表示されなくてもよい。
3. 「受信検証 A/B」を一度開く。外部アプリの共有シート下側のアクション一覧から「JibunKitへ保存」を使用（上段の共有先「JibunKit」とは別）。代表の文字列またはURLをAへ保存・取込みし、Bが増えないことを確認。一度取消して未取込みが増えないことも確認。残るファイル入力とA無効化/B保持は[Action手順](2026-09-18-p2-ar-action-device.md)にまとめる。
4. 「Appearance A」のenvironment=dark、「Appearance B」のenvironment=lightを確認。Aで「画面を点灯し続ける」をオンにしてrequested/effective=trueを確認し、通常の自動ロック時間を超えて消灯しないことを確認。トップへ戻れば通常の自動消灯へ戻ることを確認。自動ロックが「なし」の場合だけ時間設定が必要。試験後は設定を戻す。表示の文字列・sheet・windowの細部は自動試験で確認しているため手作業で繰り返さない。

途中で異常があればそのまとまりを止め、表示を報告する。後続のBLE/iPad/位置は機器と時間の条件が整ってから。同じIPAを維持し、まとまりの最後に通常IPAへ戻す。CloudKit/APNsの1.0判定条件は別質問の回答を待つ。

## 受領した実機結果（統合候補c66b624）

- AR: 初回は`featureConsentDenied(JibunKitCore.MiniAppCaptureResource.camera)`。管理画面のFeature別カメラ同意を許可するとframesが増加し、トップへ戻って再入場すると停止。再開始で増加・明示停止も成功。初回拒否は同意未許可であり、OS権限拒否やAR非対応とは区別する。手順の設定場所を補足した。
- Action: Safari共有シート下側の「JibunKitへ保存」からURLをAへ保存・取込み、B保持。取消後に未取込み件数とA/B内容が増えない。小さいテキストファイルをBへ保存・取込み、A保持。A無効化時にAへ受付不可、Bへの保存・取込みは成功。ユーザーのOKは提示した二択（A非表示または拒否）のどちらかまでは特定していない。
- Idle: Appearance Aの要求をオンにしてrequested/effective=true、通常自動ロック時間を超えて消灯せず、トップへ戻ると通常消灯する一続きの手順にOKを受領。

今回のOKから、別途案内していない外観A/Bのdark/light、Counter/Reminderの更新保持、通常IPAへの復帰、AR無効化・OS割込み、BLE/iPad/実位置受信まで確認済みとはしない。P2全体の完了や正式版公開ではない。

## BLE実機で検出した診断UI修正

Android GATT設定・広告準備後、ユーザーの画像でBLE SensorのForm同一行にスキャン/停止等の標準Buttonが隣接していることを確認。スキャン意図の操作後に状態はスキャン停止。両action発火の実測ログはなく因果は未確定だが、Formの行actionの曖昧さを除去するため全5組（scan、service検索、characteristic検索、read/write、subscribe/unsubscribe）をそれぞれ独立行へ変更し、scanは開始/停止を明示する。通信・所有者の実装は変更しない。

修正版はp2-combinedの既存69 native/Release検査を一括実行し、実機で単独scanと後続通信を再開する。既存AR/Action/idleの結果は保持。表示修正のため通常回帰全体は再投入しない。Androidは利用可能、iPadはユーザー申告で約3時間後目安（利用開始を自動的に仮定しない）。

修正版afd9086187ebd3105a98d68386c0704ee9ea3569は[CI35306613429](https://github.com/y-aplus/JibunKit/actions/runs/35306613429)でnative69件成功（failure0/skip0）、Release/IPA検査成功。所要15分11秒。[修正版IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-ble-ui-check-20260918/JibunKit-P2-combined-check.ipa)を公開し、無認証再取得のSHA-256 `9d380452e4560298917ac507ee654717801807166a0fe650c245c5adc10c54df`と全entry CRC一致を確認。6,386,486 bytes。UIの実タップとBLE無線は未確認で、69 native試験で代用しない。元候補c66b624のAR/Action/idle実機結果は維持する。

## BLE同一機器の複数owner: 実機失敗と切り分け

修正版afd9086で単独Sensorのscan/接続/service/characteristic検索、write `03 04`とreadback、notify `05 06`、unsubscribe後は`07 08`を送っても値維持、resubscribe後`09 0A`受信に成功。Android操作時はほぼ毎回ChatGPTが前景で、JibunKit復帰後に値を確認したとの補足を受領。背景送信→復帰後の受信確認として記録し、callback処理が背景中だったか復帰直後だったかは未判定。

Accessoryも同じperipheralへ接続・購読中表示。しかし`0D0E`はSensorだけ受信しAccessoryは未受信。Androidの接続タブは1つ。Sensorのみ管理から無効化するとAndroidの通知矢印が消え、次の送信不可。Sensor単owner成功と併用時の未受信を区別し、B維持を合格にしない。Accessory単独での通信は未確認のため、複数owner干渉が原因と確定したわけではない。既存fakeはowner別に独立し、共有native object/物理購読の競合を検証していない。

初期修正はdiscovery/retrieve時の不要なdelegate再代入の除去と、接続中objectをscan結果で置換しないこと。connect/restorationのdelegate設定は維持する。これだけで修復したとは断定しない。診断fixtureが任意sinkを注入し、manager/peripheral object identity、delegate owner、generation、notify request/callback、value、cancel/disconnectを80行の共有ログに収録・共有できるようにする。ペイロード本文は記録しない。通常利用ではsinkなしで記録しない。別project workerのソースレビューでも、delegate奪取とOS/peerのlink/CCCD共有をtraceで区別してから恒久修正する方針を確認した。

AppleのcancelPeripheralConnection資料は他アプリの接続が物理linkを維持し得るとするが、同一アプリの複数managerの隔離を今回の結果に代えて保証しない。もし同一objectまたは購読/切断の共有が確認されたら、peripheral単位のdelegate/接続interest/購読者管理と応答所有者の調停が必要。単純なcallback全owner転送ではread/writeの帰属が崩れるため行わない。

ユーザー指摘により、Accessory単独でのread/notify成功が未確認である点を明示。次の実機切り分けはSensor無効・Accessoryのみを新規接続して受信確認→Sensor追加後の双方受信→Sensor停止後Accessory維持の順にする。Accessory単独で失敗する場合はその段階の記録で止め、共有transport説を先行確定しない。

診断修正fe1a6e5708fa5de4eb5fa855748cc8b661eb5e18は[CI35309744549](https://github.com/y-aplus/JibunKit/actions/runs/35309744549)でnative69件（failure0/skip0）、Release/IPA検査成功、13分33秒。[診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-ble-trace-check-20260918/JibunKit-P2-combined-check.ipa)を公開し無認証GET/SHA/全entry CRC照合済み。6,403,421 bytes、SHA-256 `ef5c53fc590741e963132b496c73a0c3abe91e8ea02a7a282e1a95b8c5fb6c38`。実機切り分けは未実施。

## fe1a6e5でのBLE再確認結果

Sensorを無効のままAccessory単独で接続・購読し、`11 12`受信成功。その後Sensorを再有効化して同じAndroidへ接続・購読すると、`13 14`は両Featureで受信。Sensorだけ無効化した後もAccessoryが`15 16`を受信した。これでAccessory単独未確認という切り分けの不足を補い、当該候補・機器・操作順における両受信と片側停止後の他方維持を確認した。

ユーザーは屋外で周囲の広告が多数表示されるためscan停止を希望。scan停止は接続解除ではない旨を案内。修正前のdelegate/object競合の内部原因はtrace未受領のため確定しない。逆順やcold復元等をこの成功から推定しない。

同じ候補でAccessoryのscan停止後に`17 18`を受信。明示切断後、同じAndroidへ再接続・service/characteristic再検索・再購読し`19 1A`受信に成功。scan停止と接続寿命の分離、および通常切断/再接続後の通知再開を実機確認。cold復元・OSによる自動再接続はこの手順の対象ではない。

## 受領traceの判定と記録量の修正

受領した80行は周囲の未接続機器のdiscovered記録が大半で、両owner併用時の記録は保持枠から失われていた。残存traceでは05:47:04ZにAccessoryのcancel/disconnected、05:47:19–20Zに同じperipheral objectの別generationでconnect/connected、05:48:28–29Zにnotify要求/成功callback、05:48:40Zにerror=false・notifying=true・2bytesのvalue callbackを確認。delegateはAccessoryで一致。これらは通常切断・再接続・通知再開を裏付けるが、元不具合のdelegate横取りやA/B object共有を確定する証拠ではない。周囲の機器ID・メモリアドレスは公開文書へ転載しない。

診断sinkの発見記録を、接続中identifierへ別objectが返された場合だけに限定する。接続/購読/callback/切断記録は維持し、通常周辺広告で重要な記録を押し出さない。製品動作は変更せず、この記録修正だけのIPA入替えや成功手順の再試験は要求しない。次の必要なCIへまとめる。

## iPad実機の見送りと独立した復元修正

iPadは利用可能になったがsideload環境がなく、ユーザーは今回の準備をpassした。iPad実機は未確認を維持し、ユーザー操作待ちから外す。Simulatorの実二window検証を実機検証へ読み替えず、1.0の条件から無断で削除しない。

独立したコードレビューで、willRestoreStateが接続世代だけ再作成し、OSが保持するservice/characteristic objectの世代索引を復元していないことを発見。再検索前に届く復元通知がcharacteristicGenerationsのguardで破棄される経路があった。接続callbackを公開する前に、復元されたGATT graphから既存native objectのままservice/characteristic索引と世代を再構成する。曖昧な重複UUIDを推測で選ばない。CBMutableService/Characteristicの実型でidentity保持・重複拒否を2件追加し、既存69件と一括native/IPA検証する。これはOSによるcold起動自体の実測ではない。

次CIはログの周辺広告抑制9811e44を含めた一括p2-combined、73 native想定、setup/upload込み15–25分（前回13分33秒）。通常owner coordinator/保存形式を変更しないため、通常IPAの全面再試験は出荷候補の版・文書整理とまとめる。実機確認ごとのminor/patch版進行は一括出荷時に行い、診断候補を正式版と誤認させない。

同じ復元経路で、restored-connectedを保留してFeature寿命の非同期起動を待つ間、後続のvalue callbackを破棄していた点も修正。接続と同じ順序で保留してconsumerへ渡し、旧generationと停止済ownerは既存guardで拒否する。早着notify/旧世代拒否/停止後拒否を1試験追加し、今回の統合nativeは73件想定。

復元起動待ちのbufferは256件を上限とし、超過時は最後の枠に明示的なfailureを保持する。切り捨てたstreamを完全配送済みとしない。超過の回帰試験も追加。独立レビューの指摘を反映し、GATT helper試験名はnative object identity構築の検査に限定した。

coordinatorの復元受付にも変更があるため、p2-combinedでも既存BLE/window共有ロジック24件のSwift Package試験を実施する。新規修正をnative試験だけで済ませず、stop/join/旧世代/復元受付の回帰を同runへ含める。setup/upload込み20–25分を見込み、shared段階は10分上限を維持。
