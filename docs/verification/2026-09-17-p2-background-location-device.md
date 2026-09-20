# P2-B 背景処理・位置情報の実機確認（修正版の起動確認済み・対象操作待ち）

## 現在の配布版: 背景配送記録

2026-09-18更新。source `f6f6c0430df1817801c9e160462e4d19e7ef505c`、0.8.3/build13。[CI35243182556](https://github.com/y-aplus/JibunKit/actions/runs/35243182556)で背景19＋位置9＝全28native method、skip/実行時warningなし。SDK27診断Release/IPAも成功（12分48秒）。公開GET/hash/CRC・tag/source・3bundle ID/版/署名resourceを照合済み。通常productionは変更がない82f61bbの検証/通常IPAを再利用し、再ビルドしていない。

[背景配送記録版IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-delivery-check-20260918/JibunKit-P2-B-f6f6c04.ipa)

継続処理のcode1について追加操作は不要。位置の既済確認も繰り返さない。次は別機構のbackground URLSessionによる通常転送を一度確認する。

1. アプリを削除せず上記IPAを上書きし、Background Aを開く。
2. 「診断HTTP URL」へ次の公開ファイルURLを貼る。このIPAは単なる転送データとして保存し、インストールしない。

```text
https://github.com/y-aplus/JibunKit/releases/download/p2-b-native-compare-20260918/JibunKit-P2-B-daa49cd.ipa
```

3. 「background download開始」を一度押してホームへ戻り、15秒ほどでJibunKitへ戻る。
4. 「背景配送記録」で「HTTP完了: ファイル保存」の有無と、「host URLSession callback受信」の有無を共有する。失敗ならエラー文を共有する。

強制終了・無期限待機は不要。小さいファイルなので前景中に完了する場合もある。ファイル保存成功と背景/OS再起動配送の成功を分けて記録する。今回は新しいHTTP機構の代表確認で、継続処理エラーの再診断ではない。OS cold配送・位置境界/電波受信は依然未実証。

## 前候補daa49cd: 同じhostでのOS直接比較

2026-09-18更新。source `daa49cd28fa611dc3067281c3abbb0a82bdd91f1`、0.8.3/build13。[CI35238784459](https://github.com/y-aplus/JibunKit/actions/runs/35238784459)で背景17＋位置9＝native26件（skip/実行時warningなし）とSDK27診断Releaseが成功。11分18秒。全宣言methodを構造化結果へ照合し、IPAのCRC・3bundle ID/版・署名resource・SDK/診断型を確認。公開IPAの無認証GET/hash/CRCとtag/sourceも一致した。

[OS直接比較用IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-native-compare-20260918/JibunKit-P2-B-daa49cd.ipa)

1. アプリを削除せず、このIPAを上書きする。
2. Background Aを開き、「OS直接比較」の「OS直接比較を一度実行」を一度押す。
3. その欄の記録全文を共有する。通常の継続処理の再試行や長時間待機は不要。

この比較は共通center/ID resolver/workerを迂回するが、hostと署名は共通。同じエラーでもOS単独の問題とは断定しない。実機で直接比較もcode1となった（下記の受領記録）。OS開始は未確認。位置/Regionの既済操作は反復しない。今回の差分は診断fixtureと文書だけで、通常/共有397件・Records11件・検索/通常IPAは82f61bbの検証を再利用し再ビルドしていない。必要時の[通常IPA（82f61bb・SDK26.5）](https://github.com/y-aplus/JibunKit/releases/download/p2-b-async-check-20260918/JibunKit-normal-82f61bb.ipa)。安定版は0.8.3のまま。

## 前候補82f61bb: iOS27非同期受付と位置受信記録

2026-09-18更新。source `82f61bb8d59bd74a5a6a3513b4fa3c68b2f48b08`、0.8.3/build13。[CI35235454126](https://github.com/y-aplus/JibunKit/actions/runs/35235454126)で共有397件（既存Keychain2skip）、Records11件、通常検索44.924秒、背景15＋位置9＝native24件（skip/実行時warningなし）が成功。通常18分06秒・native10分50秒。

[新しい診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-async-check-20260918/JibunKit-P2-B-82f61bb.ipa) ／ [同source・従来SDKの通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-async-check-20260918/JibunKit-normal-82f61bb.ipa)

今回の診断はXcode27/Swift6.4/iOS27 SDK製で、iOS27で新しいcompletion受付を使用する。通常版はXcode26.6/iOS26.5 SDK製で旧同期fallbackを保持する。同一sourceでも両IPAのSDK経路は同じではない。実機では新APIからBGTaskSchedulerErrorDomain/code1とduetactivityscheduler接続のエラーを受領。受付失敗を画面へ配送できたが、OS開始は未確認。

削除せず診断IPAを上書きし、Background Aで「継続処理を即時開始」を一度押す。「継続処理の記録」に「受付API: 非同期completion」があることと、その後の受付応答/進捗を確認する。進まなければ記録全文を共有し、反復や無期限待機は不要。位置/Regionの既済手順を再要求しない。

位置記録は「受信記録（座標なし・最新64件）」へ保存する。callback受信時の時刻・UIApplication状態・process識別子を残し、画面表示/再起動で消さない。Regionにも「位置更新停止」を追加した。単にprocessが変わっただけでOSが位置イベントを理由にcold起動したとは断定しない。破損記録は保存失敗を表示して既存ファイルを保持する。

公開tag/source一致、2IPAの無認証GET・SHA-256・全entry CRC・3bundle ID/0.8.3/build13・署名resource・診断非混入を確認。診断binaryに新submitTaskRequest completion selectorと位置記録型があることも確認済み。ZIPは追加していない。安定版は0.8.3のまま。


## 前候補8b3584a: 同期APIによる即時開始の診断

source `8b3584a74e6a49c99fedfbe5b0b0fd6e8a5b9816`、0.8.3/build13。[CI35231831131](https://github.com/y-aplus/JibunKit/actions/runs/35231831131)は共有395件（既存Keychain2skip）、Records11件、通常検索UI（38.205秒）、背景14＋位置7＝native21件（skipなし）、通常/診断IPAが成功。通常15分43秒・native11分35秒。structured xcresultの全宣言methodをsourceに照合済み。

[即時開始を確認する診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-admission-check-20260917/JibunKit-P2-B-8b3584a.ipa) ／ [同sourceの通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-admission-check-20260917/JibunKit-normal-8b3584a.ipa)

アプリを削除せず診断IPAを上書きし、Background Aで「継続処理を即時開始」を一度押す。進捗増加か、受付失敗の文言（domain/codeを含む）を確認する。受付済みのままなら「継続処理の記録」の内容で切り分け、開始の反復や無期限待機を求めない。位置の既済手順は繰り返さない。以下の前候補のOS成功をこのsourceの実測へ読み替えない。

新規prerelease `p2-b-admission-check-20260917`のtag/source一致、2IPAの無認証GET・SHA-256・全entry CRC・3bundle ID/版・署名resource・診断構成/通常版非混入を確認した。追加ZIPは作らない。作業中の永続的な位置受信記録はこのIPAに含まれない。


## 前候補3af8e32で受領済みの実機結果

対象は`3af8e32532e2fb2b1759920da7a716a00639de10`、0.8.3/build13。[CI35180204806](https://github.com/y-aplus/JibunKit/actions/runs/35180204806)で共有393件（既存Keychain2skip）、独立Records11件、通常検索UI、背景/位置native19件（skipなし）と通常/診断IPAが成功。通常11分52秒・診断8分52秒。再署名ID対応、Aの起動登録失敗後もBを登録できること、部分登録の重複実行を避けること、有効化/復元で失敗ownerの開始禁止を迂回しないことを自動検証した。

[修正版診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-P2-B-3af8e32.ipa) ／ [修正版診断ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-P2-B-3af8e32.zip)

[同sourceの通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-normal-3af8e32.ipa) ／ [通常ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-launch-check-20260917/JibunKit-normal-3af8e32.zip)

2026-09-17、ユーザーから「とりあえずアプリは開いたよ」と受領。修正版の起動成功のみ確認済み。「準備失敗」表示の有無やscheduler実行成功までは確認していない。継続処理と位置の追加観測は以下のとおり。

追加観測: Background Aで開始後、進捗0/60・「受付済み」とユーザー報告。実際の待ち時間は未計測で、OS launchは未確認。現診断は`.queue`を使用するため、受付だけでは即時起動を保証しない。追加待機や開始の反復を求めず、「継続処理を取消」後に「取り消し済み」になったと受領。これは画面上の取消完了であり、OSで実行された証拠ではない。OSの資源待ちと配送不具合は現表示から識別できない。次の診断改善に、即時開始できなければ失敗を返す`.fail`経路、NSError domain/code、時刻付き受付/launch/取消記録（このprocess中の最新32件）を実装した。まだCI/配布前なので現行IPAにはない。実機の原因は未確定。[Apple queue仕様](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest/submissionstrategy/queue)。

位置更新の追加観測（同じ3af8e32診断IPA）: 「前景位置更新」で緯度・経度が表示されたと受領。続く背景位置更新→ホーム画面→アプリ復帰の確認について、ユーザーは屋内・歩行なしでevent数増加と位置表示の小さな変化を報告した。前景位置取得と復帰時点での更新は確認済み。現表示に配送時刻/scene状態がないため、背景中の配送と復帰直後の配送を区別せず、物理移動/geofence進退の証拠にも読み替えない。続けて「位置更新停止」を押したと受領。ボタン操作まで確認し、以後のevent停止を継続観測した証拠とは区別する。座標の具体値は収集していない。

Region/iBeaconの追加観測（同じ3af8e32診断IPA）: Feature位置同意→現在地取得→半径150mでgeofence登録→診断iBeacon登録→`geofence-1`と`diagnostic-beacon`の一覧表示→各行の解除で消える、という一括手順にユーザーから「OK」を受領。登録/一覧/解除の通常操作を確認済み。境界通過、送信機の実電波、cold配送を確認済みにはしない。現在地取得は継続更新を開始する実装で、この画面には停止ボタンがないため、片付けとして管理画面の当該Feature位置同意を「拒否」へ戻したと受領（会話で案内した「許可しない」は誤記で、実表示は「拒否」）。

修正版IPAで3bundleの既存ID/0.8.3/build13、追加したbuild時ID metadata、診断5scheduler/3background modes、通常版の診断非混入、CRC/署名resourceと一重ZIPを照合済み。新規prerelease `p2-b-launch-check-20260917`を同sourceへ固定し、診断/通常IPA・ZIPの4assetを無認証GETで再取得。SHA-256・CRC・ZIP内IPA一致を確認済み。旧tag/assetは移動・差替えしていない。修正版の実機起動成功を受領した。前景位置取得と復帰時点の更新を受領。継続処理のOS開始は未確認。

## 旧候補で確認した起動不具合

**以下のda62672診断版は実機で起動直後に終了したため、確認を中断する。再試行不要。** 添付クラッシュ記録のapp binary UUIDが配布IPAと一致し、main threadの`NotificationAppDelegate.application(_:didFinishLaunchingWithOptions:)`で`EXC_BREAKPOINT/SIGTRAP`を確認。元のthrowされたエラー文は記録になく、SideStoreの許可ID書換え→旧ID登録拒否はコードからの有力な推定である。端末識別子やログ全文はリポジトリへ保存しない。復旧用には[安定版0.8.3 IPA](https://github.com/y-aplus/JibunKit/releases/download/0.8.3/JibunKit.ipa)を削除せず上書きできる。

修正では実行時の許可リストに一致する再署名後IDへnative register/submit/cancelを統一し、Feature起動登録の失敗を全appのtrapに変えず、当該ownerの開始拒否と画面表示へ変える。修正版CIと実機起動は成功。修正版の対象操作の観測は冒頭に記録。以下は旧候補の手順と証拠として保持する。

対象sourceは`da6267213a15872f3eb3860157edf0840e866bd2`、0.8.3/build13。[CI35176070341](https://github.com/y-aplus/JibunKit/actions/runs/35176070341)で通常版と背景/位置native17件・診断版が成功。正式0.8.4の出荷確認ではない。実機で確認した成果のまとまりを次の版へ進める。

[診断IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-P2-B-da62672.ipa) ／ [診断ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-P2-B-da62672.zip)

[戻す通常IPA](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-normal-da62672.ipa) ／ [通常ZIP](https://github.com/y-aplus/JibunKit/releases/download/p2-b-device-check-20260917/JibunKit-normal-da62672.zip)

アプリを削除せず上書きする。ZIP内は同名IPA一つ。異常時はその画面の文言と直前の操作を伝え、その項目の反復は不要。会話では一まとまりずつ案内し、返答ごとのcommit/pushや全管理・復元マトリクスの反復は行わない。

## 最初に確認する継続処理

「Background A」→「継続処理を開始」。開始できれば進捗が0から増える。ロック画面でも継続処理の表示が出て進むか確認する。

60秒で終わる前にロック画面側で取消できれば一回取り消し、アプリへ戻ってAが停止したことを確認する。表示や取消操作が見つからない、または「受付失敗」なら、その文言を報告する。「受付済み」だけではOSが実行した証拠にしない。

その後「Background B」で開始し、今度は取消せず完了を待つ。アプリ画面で「進捗60/60」「成果1」になることを確認する。OS都合で開始されない場合、時間を決めずに待ち続けない。

## 継続処理の次に確認する位置更新

管理画面で「位置更新Probe」の位置情報を「許可」にする。「位置更新Probe」→「When In Use許可を要求」でiOSの使用中許可を与え、「前景位置更新」で緯度・経度が表示されることを確認する。座標そのものを報告する必要はない。

「背景位置更新」を押し、ホーム画面へ出て少し歩いた後に戻る。event数や位置が更新されたか確認し、最後に「位置更新停止」。屋内・静止中に更新がないことだけでは不具合と判定しない。こちらは必要になった段階で会話から案内する。

## まだ完了にしない項目

- refresh/processing/shared refreshの受付と、OSが後から選ぶ実起動・期限は別。画面の受付表示や注入callback成功を実OS起動へ読み替えない。
- 実HTTP転送のA取消/B保存は今回のSimulatorで成功。OSが終了したappを再起動して配送するcold再接続は未確認。アプリスイッチャーで強制終了する操作を、OS終了と同一に扱わない。外部HTTPの準備とcoldイベントを読み取る診断が必要であり、今は手元の任意URL入力を依頼しない。
- geofenceの実進退・再起動後配送、iBeaconの実電波配送は未確認。iBeacon送信機材の有無を別途確認する。現診断はUUID `E2C56DB5-DFFB-48D2-B060-D0F5A71096E0`、major1/minor1。機材がない場合は自動配送試験の成功で実測済みにしない。
- Regionのcold callbackはアプリ画面を開く際の状態表示に上書きされる可能性がある。現在の画面文言だけでcold配送時刻を断定せず、必要な観測を整えてから依頼する。
- これらの残件があるため、最初の継続処理・位置更新が成功してもP2-3/P2-4全体をcompleteへ変更しない。

## 自動試験と出荷物の証拠

source `da62672`で共有389件（既存Keychain2skip/失敗0）、独立Records11件、通常検索UI、背景10件・位置7件のnative試験（skip/失敗0）が成功。通常job14分13秒、診断job7分24秒。所有/管理/復元/世代/期限/失敗/B保持、実HTTP A取消・Bファイル保存、実CoreLocation設定とSDK値を対象とする。OS schedulerの起動や物理移動は注入試験から推定しない。

IPA全entry CRC、app/Widget/Shareの既存IDと0.8.3/build13、署名resource、診断構成の5scheduler宣言と3background modes、通常版の診断非混入を照合。各ZIP内IPAの一致を検査した。新規prerelease `p2-b-device-check-20260917`を同sourceへ固定して公開。診断/通常のIPA/ZIP計4assetを無認証で再取得し、SHA-256・CRCとZIP内IPA一致を確認済み。既存tag/assetは差し替えていない。

旧候補で受領した実機結果は起動直後終了のみ。修正版の起動成功は冒頭へ記録した。継続処理のOS開始は未確認。位置の実機観測は冒頭に記録した。

## 位置記録を準備した経緯（82f61bbでCI・配布済み）

位置callbackの受信時刻・UIApplication状態・process識別子・イベント種別をowner別の診断ファイルへ原子的に保存し、最新64件を画面で確認できる診断を準備し、82f61bbでCI・配布まで完了。座標は記録しない。既存ファイルの破損は上書きせず表示する。processが変わっただけでOSのcold起動原因を断定しない。Region画面にも位置更新停止ボタンを追加する。CI35231831131/source8b3584aには含めず、CI35235454126/source82f61bbへまとめた。

iBeacon機材について、ユーザーはAndroidスマホを所有し、iPadは明日以降利用可能と回答。AndroidのBLE advertising/iBeacon送信可否は未確認。アプリ導入や外出はまだ依頼していない。

送信機の一次資料: [Android BluetoothAdapter](https://developer.android.com/reference/android/bluetooth/BluetoothAdapter)はBLE advertisingの機種対応確認が必要。[AppleのiOS機器送信](https://developer.apple.com/documentation/corelocation/turning-an-ios-device-into-an-ibeacon-device)はBLE対応と送信appの前景維持が条件。手元機材での送信成功は未確認。

## 8b3584aの即時開始でもOS通知がない観測

ユーザー記録は2026-09-17T14:33:53Z「要求 即時 job=DE7832BE」、同時刻「submit成功（OS開始とは別）」のみ。進捗は増えず受付済み・OS開始未確認。明示的に`.fail`を選択したことを確認したが、旧同期APIが返した成功であり、OS側の全受付エラーがないとは言えない。[Apple DTS](https://developer.apple.com/forums/thread/807370)と[新API](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/submittaskrequest(_:completionhandler:))は、旧submitに全エラーを返せない場合がありiOS27のcompletion方式で補うと説明する。今回の根本原因をOS不具合と確定しない。

次の一括検証ではXcode27/Swift6.4のSDK宣言を使う非同期受付と、上記の位置受信記録を統合する。通常Xcode26.6の互換経路も同runで検証する。ユーザーへ開始の再連打・無期限待機・端末の初期化等を求めない。

## 新APIで受領した実機エラー（82f61bb）

2026-09-18、ユーザーOCRで`BGTaskSchedulerErrorDomain`、code1、`connection to service ... named com.apple.duetactivityscheduler`を受領。processのpidは診断の比較に必要ないため記録を省略する。新APIが受付失敗をFeature画面へ返すことは実機確認済み。仕事のOS開始成功ではない。

[Appleのunavailable説明](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/error/code/unavailable)はバックグラウンド更新無効等を挙げる。全体/当該appの設定を一度だけ確認依頼し、変更・再試行は要求していない。[一致する接続文言の報告](https://developer.apple.com/forums/thread/838434)ではApple DTSが内部型のNSSecureCoding失敗を説明するが、今回の端末からはその詳細stackを受け取っていないため同一原因とは確定しない。iOS27原因説、署名制限、Feature実装不備のいずれにも固定しない。

次の切り分けは設定の観測を先に反映し、必要なら同一host/署名で共通centerを通さない最小native経路と実際のbundle-prefix/許可list条件を一つの診断境界で比較する。端末初期化、時刻変更、全件のsysdiagnose提出は現時点では依頼しない。既知報告の再現手順をユーザーへそのまま転嫁しない。

## Background Refresh設定の照合と直接比較の準備

ユーザーは全体とJibunKit個別のバックグラウンド更新が有効、Wi-Fi限定だが現在Wi-Fi利用可能な環境と回答。端末がその時点で接続していたことやOS内部サービスが正常なことまで推定しない。設定無効を原因に固定せず、同一host/署名で共通center・ID resolver・execution adapterを通さない直接native経路を準備する。

新しい「OS直接比較」は実際のCFBundleIdentifier＋owner別export namespaceからunique IDを構築し、同じprefixの許可wildcardがなければ未送信として明示する。登録・即時要求・非同期受付結果・OS callbackを記録し、callbackが来たら試験仕事を即完了する。共通実装と異なる経路で同じエラーなら、共通centerの配送処理が原因という可能性を狭められる。単独別appではないため、host構成・署名・OSのどれかを確定する証拠にはしない。取消/Feature停止は直接要求も閉じ、遅い受付応答やcallbackが次の仕事を再開しない。daa49cd/CI35238784459で自動試験と診断IPAを検証して公開済み。実機結果待ち。

## 時刻付き位置記録の実機観測（82f61bb）

ユーザーの記録に、同一process識別子で次の配送が含まれた（座標は含まれない）。2026-09-17T15:06:01Zは`background`のhost起動hookとOS許可callback/whenInUse。15:16:51Zは`active`のruntime接続。15:17:00Zは`active`で背景位置更新を開始、OS許可callback/whenInUseと位置callback1件が2回。15:17:30Zは`active`で位置更新停止。

この約30秒の確認では背景中の位置callbackは未観測。起動hook・許可callbackのbackground表示を位置の背景受信や位置イベント起因のcold起動へ読み替えない。時刻/app状態を分ける診断と停止記録を実機確認した。歩行は要求しておらず、背景設定のdistanceFilter10mと屋内静止でeventがないことだけでは配送不具合と判定しない。今すぐ同じ操作を反復させず、実移動/region進退の証拠は未確認として残す。

## 直接比較の実機結果（daa49cd、2026-09-17T15:36:33Z）

ユーザーOCRで実bundle prefix/許可wildcard一致、appState=0（active）、refresh=2（available）、lowPower=false、native登録成功の後、BGTaskSchedulerErrorDomain code=1、com.apple.duetactivityschedulerへのconnectionエラーを受領。共通center/ID resolver/execution adapterを迂回しても同症状。共通経路だけの不具合ではないが、同じhost/署名なのでOS単独原因や署名条件の完全正常を断定しない。OS開始は未確認のまま。再インストール・設定切替・要求反復は依頼しない。

[Appleの同症状報告とDTS回答](https://developer.apple.com/forums/thread/838434)には内部NSSecureCoding failureが説明されるが、今回その詳細stackを取得しておらず同根とは未確定。[API実行threadについてのDTS回答](https://developer.apple.com/forums/thread/840876)も確認し、off-main必須というguideの断定を訂正した。off-main実装自体を原因扱いして変更する根拠はない。

## 次の独立検証: 通常scheduler/URLSessionの永続受信記録

通常/共有scheduler、host URLSession再接続、delegate完了、runtime受付拒否/cleanupをowner別に最新64件保存する診断を追加。時刻・app状態・processを残し、再起動だけでOS起動理由を断定しない。HTTP URL・内容・NSError userInfoは永続記録へ含めない。保存上限、再読込、A/B分離、破損保持と実Feature配送順序を自動検証する。診断fixtureのみ変更し、通常productionのCIは再利用。f6f6c04/CI35243182556で28件と診断IPAを検証・配布済み。daa49cdには含まれない。外部HTTP経路の準備とOS cold配送の実証は別途残る。

2026-09-18追記: ユーザーはiOS側問題への十分な確信があれば追加追究不要と指示。直接比較までの結果をもって継続処理の追加診断は一旦停止する。OS開始を確認済みにはせず、host/署名との完全分離がない限界を残す。独立した通常/共有/HTTP観測のCI35241889661はテスト構文エラーで実行前に停止。修正して同じ28件を再検証する。ユーザーへ追加操作は依頼しない。

## HTTP転送の実機結果（f6f6c04）

ユーザー記録: 2026-09-17T16:14:13Z backgroundでhost起動hook/背景登録完了、16:14:23Z activeでruntime接続、16:14:36Z activeでHTTP転送要求、16:14:37Z activeでHTTP完了: ファイル保存。同一process。公開IPAを使った通常転送/保存は成功。host URLSession callback受信は記録になく、背景再接続/cold配送は未観測。最初のbackground起動hookをHTTP起因の起動と解釈しない。同じ短い転送を反復するよう依頼しない。

## 次の背景移行確認: 少量の低速応答（再ビルド不要）

小さい公開IPAは実機で1秒で完了したため、同じファイルを反復しない。HTTPテストサービス[httpbingoのdrip](https://httpbingo.org/)へGETし、`https://httpbingo.org/drip?duration=10&numbytes=10&delay=0&code=200` がこのPCからHTTP200・10bytes・11.24秒で完了したことを確認。20秒指定はサービス上限10秒により400、4096bytesの細かい分割は応答が長引いたためローカル試験を中断し、手順には採用しない。

現行f6f6c04で上記10bytesのURLへ差し替え、開始直後にホームへ戻り20秒後に復帰する。背景配送記録の新しい行を共有し、active/backgroundとhost URLSession callbackの有無を分ける。第三者テストサービスへ個人データは送らずGETのみ。OSのcold起動を保証する試験ではなく、前景完了との区別を目的とする。転送の実機結果は未受領。

## 低速HTTPの背景配送実機結果（f6f6c04）

ユーザー記録: 2026-09-17T16:21:10Z activeでHTTP転送要求。16:21:22Z backgroundでhost URLSession callback受信→HTTP再接続受付・delegate待ち→ファイル保存→全delegate完了・host completion解放。同一process73C04016。OSからhostへの背景通知、Feature再接続、ファイル保存、完了通知の順序まで代表実機確認成功。終了したprocessのcold再起動とは区別する。この背景通信手順の反復は不要。継続処理code1の追加追究停止とは別機構の成果である。
