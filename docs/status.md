# Release and development status

Updated 2026-09-20. **Stable: 1.0.0/build16.** The adopted P0/P1/P2 criteria were published after the final document and artifact audit. The explicit unobserved conditions remain disclosed below.

- Build source: `82553cfe2c81cd83111cd2a247c90f87bd1015ac`; CI35409750733 passed shared443 tests (2 existing skips), Module11, normal IPA checks and the selected cold/warm URL regression.
- Normal IPA: 4,747,918 bytes, SHA-256 `6d077f2caf52f9a1151e0e00cdb02332536baaed922e977b1ac0e7afe3e84d3f`. App, Widget and Share report 1.0.0/build16. It is published at the 1.0.0 release.
- Normal product code matches the physically checked0.8.5 source apart from version metadata. Later diagnostic results include device cross-process HTTP restoration and Simulator terminated-process Region enter/exit.
- CloudKit/APNs remain optional, signing/service-dependent and live-communication-unverified. Generic HTTP ownership remains in the normal scope.
- Accepted unobserved conditions remain explicitly unverified: physical location/iBeacon conditions, BackgroundTasks OS launch/expiration, physical iPad windows and AR OS-interruption recovery. See the [acceptance record](verification/2026-09-19-final-observation-boundary.md).
- The final document audit and release artifact checks are recorded in the 1.0.0 verification record. No new device test is required by the adopted boundary.

See [release preparation](verification/2026-09-19-1.0-release.md), [scope plan](delivery/plan.json), [compatibility](compatibility.md) and [published0.8.5 evidence](verification/2026-09-18-0.8.5-release.md). The broader D ledger includes future generalization and must not be interpreted as a list of all v1 release blockers.

<details>
<summary>Historical development observations before v1 acceptance (Japanese)</summary>

The following preserves dated/source-specific history. Its pending-state statements describe those earlier checkpoints, not current release status.



更新日: 2026-09-19。公開版/mainは0.8.5/build15（前版0.8.4/build14）。通常IPAのbuild sourceはfeab170、CI35357260854成功。上書き後のCounter/Reminder保持と前景復帰後の表示・操作を実機確認。[出荷記録](verification/2026-09-18-0.8.5-release.md)。当時は1.0未完。実位置/電波、署名条件付き通信、AR実OS中断等の残件を維持する。iPad実機はユーザーが見送り、待機対象ではない。

## 0.8.4後の検証

AR診断ddb0f83はCI35336219498のnative17件と実機のcamera競合一周が成功。[AR記録](verification/2026-09-18-ar-followup.md)。OS interruptionは別の未観測項目。FilesのCI失敗はJibunKit非依存のUIKit/SwiftUI双方でも同じFileProvider参照解決エラーが再現し、今回の反復を終了した。[独立比較](verification/2026-09-18-files-independent-comparison.md)。BLEは新processでOS復元と同一世代Notifyを実機確認済み。scene別選択復元はSimulatorと通常版の限定回帰を確認し、0.8.5へ反映した。

保存専用Action（P2-13）は5a97857/CI35343811711と既存source別実機/共通入力証拠を照合して採用範囲を完了。[判定記録](verification/2026-09-18-ar-followup.md)。P2-6もCI35347692100のOS言語表示確認を含め採用範囲を完了。

P2-9（BLE）は実機の通常通信・両owner/管理・新processの同一復元世代NotifyとCI35352655988のnative回帰を照合し、採用通常範囲を完了。OS自動起動の契機は未判定であり、起動時刻の保証はしない。P2-3はSimulator背景位置callbackを確認したが実電波等の残件を維持する。P2-11は99632e3/CI35355170934で保存した元の二session・owner・値の再接続と片側破棄/他方保持が成功。物理iPadは未確認で操作待ちではない。通常版のcold URL優先もCI35357260854で成功。

P2-8/P2-10の採用通常範囲は完了。通常HTTP/通知の実機証拠、identity/pushのnative所有者・管理・delegate接続、後続共有管理変更の回帰を[最終照合](verification/2026-09-19-p2-identity-push-final-evidence.json)した。署名専用実通信は承認済み未検証であり、通信成功や正式出荷の全件文書監査とは区別する。

## 現在の外部条件

0.8.5の通常CI35357260854と実機代表1–2は成功。共有443件（既存skip2）・Module11件・選択復元/cold URL優先UIと通常IPAを確認した。4a1340a/CI35365770330でnative87件・OS UI6件が成功し、Simulator geofenceの実enter/exitも確認。背景HTTPは実機で別processの同一転送に対するOS callback・owner再接続・保存・completion返却chain成立を確認した（[記録](verification/2026-09-19-background-http-device.md)）。OSの起動契機は未判定。ユーザーの停止解除を受け、0daaeb9/CI35371803883ではSimulator終了後のenter/exitを別background processとowner永続ログで確認（86.643秒、skipなし）。残件の最終照合を進める。現在の追加実機操作はない。

2026-09-19、ユーザーがCloudKit/APNsを通常利用の前提にしないと確定。既存実装は署名・サービス条件付きの任意機能として残し、実通信未検証を明記して1.0の必須実通信検証から外す。汎用HTTP等による外部同期と所有者分離は必須範囲を維持する。[変更後の契約](delivery/P2-identity-push-contract.md)。加入・購入や検証環境の再準備は依頼しない。

## 0.8.4へ至るsource別履歴

以下は当時の状態・未統合表記を保持した履歴。現在の公開範囲は上記出荷記録を正本とする。

未出荷統合候補の基点は`codex/p2-ar`のc66b624。[CI35300688982](https://github.com/y-aplus/JibunKit/actions/runs/35300688982)でiPad Simulator native69件（failure0/skip0）、全19 Feature実host起動、外観/翻訳/用途説明、統合IPA検査が成功（14分37秒）。診断IPAと戻し用通常IPAを[公開・取得照合済み](verification/2026-09-18-p2-combined-device.md)。c66b624実機でARのframe受信・離脱停止・再開/停止、ActionのURL/ファイル所有者別取込み・取消・A無効化/B保持、idle点灯維持/通常消灯復帰を確認。残る実機確認とCloudKit/APNs署名条件の1.0判定があり、0.8.4正式公開とmain統合を準備中。P2-F全体は未完了。

P2-I外部データidentity/Pushは`codex/p2-identity-push`で実装・自動試験まで進行。通常CI35249566535で共有415件（既存Keychain skip2）・Records11件・通常IPA・検索UI、診断CI35253192466でnative12件（skip0）・診断IPAを確認。実署名CloudKit通信/APNs配信は未確認のためP2-8/P2-10はpartialを維持し、0.8.4へ統合済みだが実通信は未確認。[証拠](verification/2026-09-18-p2-identity-push-evidence.json)。BLE/通常複数window（P2-S）の実装は0.8.4へ統合済み。以下は初期検証の経緯で、追加検証は末尾を参照。実WindowGroup接続、管理/復元時のscene資源解放、診断host/iPad選択の準備を追加し、関連ローカル19試験が成功。BLEの取消join中の再接続などを修正し、c35afe7の診断CI35292107259でiPad実windowを含むnative9件とIPA検査が成功（11分16秒）。同sourceの通常/shared CI35292105440と追加検証35293163823はcancelled。通常runの共有scene試験で、保持したcleanupの解放前にそのjoinをawaitする試験自身のデッドロックを特定し修正。修正後b2f9a04のCI35295505063で共有24件・native13件・診断IPAが成功（11分47秒）。復元BLE ticket/診断UIを含む。通常CI35295502996は共有439件（既存skip2）・Records11件・通常IPA/buildに成功し、FilesでJSON選択後のUI遷移だけ失敗。809822a/35296983783のfilename tapも失敗したが、41c97f1/35298791125で選択rowのenabled/hittableを確認し、icon位置操作から復元取消・実復元・再起動後Counter/Reminder保持まで成功（UI163.097秒、共有443件も成功）。過去のlabel tap無反応の内部原因は断定しない。BLEは後続fe1a6e5で単独read/write/notify、両Feature通知、Sensor無効化後Accessory維持、scan停止・切断/再接続後の受信を実機確認。CI35309744549はnative69件成功。旧不具合の内部原因は未確定。当該時点ではcold復元と実iPadは未確認。後続の実BLE復元証拠は末尾に追記した。周辺広告抑制と復元通知修正は7e4c740/35325946663でnative73・共有24件成功。[作業契約](delivery/P2-ble-scenes-contract.md)。iBeaconの実受信は未確認、継続処理code1の追加追究は停止。

P2-Fの通常ARはIssue #6と既存Captureの再利用可能性を照合して採用範囲を確定し、`codex/p2-ar`で実装を開始。開始元sceneの明示束縛、native ARSession接続、旧callback世代の拒否と停止cleanup保持を追加。P2-13は既存受信処理を再利用するoptional保存専用Action extensionを採用し、Shareと共通controllerへ接続した。41c97f1/35298792032でAR/Action native9件（skip0）と診断IPA/取得SHA・CRCを確認（8分41秒）。後続の外観/翻訳native試験はc66b624で成功したが、実frame/Action OS入口の代表操作は受領済みだが残件を維持するため、P2-12/P2-13はpartialのまま。[契約](delivery/P2-ar-contract.md)。

P2-6はidle/外観・Spotlight選択item・Widget翻訳・採用P2権限用途説明を採用し、既存成果の再利用と追加fixtureのnative検証が成功。idleの実点灯/通常消灯復帰は確認済み。18a94bd/CI35347692100で代表OS描画2件も成功し、既存証拠と合わせ採用範囲はcomplete。[採用契約](delivery/P2-adoption-contract.md)。

P2-1/P2-2の採用通常範囲はcomplete。306874fで再生/録音・写真/音声動画、a142108で文書保存/取消・QR・イヤホン抜去停止・通常版復帰後の既存データ保持を確認。native28件と通常通知UIはCI35102558612のsource付き証拠を、版変更だけの出荷へ再利用した。写真初回の不明エラー、以前のLive B単発値差分は原因未確定として保持。1.0全体は未完。P2-B/P2-Iの残る実OS検証と、開発中のP2-Sを分けて管理する。以下の旧版節はsourceを明示した履歴。

## 開発中の背景処理・位置情報

**P2-Bは起動修正と背景HTTP callbackを実機確認済み。継続処理の受付失敗は直接APIでも再現し、追加追究を停止している。** SIGTRAPの起動処理を特定。再署名後の背景ID対応とFeature別の起動失敗処理を追加し、3af8e32/CI35180204806で共有393件（既存skip2）、native19件と通常検索/両IPAが成功。修正版の実機起動成功を受領。継続処理Aは受付後0/60のままで、取消表示を確認。継続処理のOS開始は未確認。位置は前景取得とホーム画面からの復帰時点でのevent増加を実機確認したが、82f61bbの時刻付き記録では開始直後active中の位置callbackと30秒後の停止を確認し、background中の位置callbackは未観測。Region/iBeaconの登録・一覧・各解除も実機確認済みで、境界通過・電波受信・cold配送は未確認。即時受付診断・時刻付き記録と取消後の遅着開始防止は8b3584a/CI35231831131で共有395件・native21件・通常検索と両IPAが成功。診断IPA公開後の実機でも即時要求・同期submit成功のみでOS開始通知がない。Appleが旧APIのエラー欠落とiOS27の非同期submitを説明しているため、新API対応と位置の永続受信記録を82f61bb/CI35235454126で一括検証。共有397件、iOS27 native24件、通常検索/両IPAが成功し診断版を公開照合済み。新APIの実機結果はcode1とduetactivityscheduler接続エラー。受付失敗の画面配送を確認したがOS開始は未確認。全体/appのBackground Refresh有効を受領し、同じhost/署名で共通処理を迂回するOS直接比較をdaa49cdへ追加。CI35238784459でnative26件と診断IPAが成功し公開GETまで確認、実機直接比較でもprefix/wildcard一致・active・Background Refresh available・低電力なしで同じcode1を受領。共通経路だけの不具合ではないが、host/署名/OSの根本原因は未確定。通常/共有は変更がない82f61bbを再利用。ユーザー指示に従い継続処理の追加診断は停止し、OS開始未確認を保持。独立した通常scheduler/URLSessionの永続受信記録は、CI35241889661のテスト構文ミスを修正し、f6f6c04/CI35243182556でnative28件・診断Release/IPAが成功。f6f6c04実機でHTTP転送要求の1秒後、active中のファイル保存成功を確認。初回はhost URLSession callbackなし。続く低速応答でbackground中のhost URLSession callback→再接続→保存→全delegate完了/host completion解放を実機確認。同一processのため終了後cold再起動は未確認。旧診断版の再試行は不要。以下のCI成功は実機起動成功を意味しない。

P2-Bの初期検証として、branch `codex/p2-background-location`のsource `da62672`では[CI35176070341](https://github.com/y-aplus/JibunKit/actions/runs/35176070341)が成功した。共有389件（既存Keychain2skip）、背景10件・位置7件のnative試験、通常検索UI、通常/診断IPAを検証。P2-3/P2-4は、実OS背景起動・位置/Region/iBeaconの実測を残すためpartial。当該CI実施時点の公開版は0.8.3。現在の公開版は冒頭の0.8.4を参照。[今回の確認範囲](verification/2026-09-17-p2-background-location-device.md)。

## 0.8.0公開版

製品source `71ef1ffb4f84442bf8853c0c2e286c2bedd81d22`、[CI34967147135](https://github.com/y-aplus/JibunKit/actions/runs/34967147135)は5分16秒で成功。共通273件（skip2、失敗0）、Records11件、通常Release/metadata/署名/IPA検査が成功した。取得IPAの全entry CRC、本体・Widget・Shareの0.8.0/build10と既存ID、診断Widget kind/resource非混入も確認済み。

| 対象 | 現在の証拠 |
| --- | --- |
| P0の保存・寿命・管理・提示・追加更新 | 0.7.0のsource別CI/実機を維持。P1で変更した寿命・管理と通常UI/Filesは後続CIで回帰確認 |
| 共有/Files入力 | 初回保存先の誤拒否を修正。4e6a3f4のnative32件・完全host OS共有/再試行に加え、実機で文字列/URL/ファイル、直接開く、取消・再試行・再起動/B保持を確認 |
| Shortcuts | 6beb877でOS発見/正負加算/候補/保存済み操作/管理、4e6a3f4で取消・保存失敗・次回成功/B保持を実機確認。修正した診断制御はnative8件と管理UIでも検証 |
| 静的Widget | 独立/統合CI、通常版から診断版への更新galleryに加え、4e6a3f4実機で追加・描画・更新・A管理/B保持・上書き/Refresh保持を確認 |
| 通知・HTTP・Web | 対象別の通常host CIと6beb877実機で確認。通知添付/action/返信/前景方針、HTTP所有store/logout、Web保存/認証取消/片側削除、HTTP/Webの更新保持を含む |
| 通常IPAへの復帰 | 4e6a3f4でCounter/Reminder保持、通常Widgetの値/遷移、既存Counter Shortcutを実機確認 |

実機確認した4e6a3f4は0.7.1/build9で、正式0.7.1を公開したという意味ではない。そこから71ef1ffの製品差分は版番号のみ。旧sourceの証拠を残し、影響のない範囲を照合して再利用した。新0.8.0 IPAそのものの実機試験や、本runでSimulatorを再実行したとは記載しない。

実機の経緯は[操作別記録](verification/2026-09-14-0.8-device-check.md)、修正・失敗runは[追補](verification/2026-09-15-p1-device-followup.md)、合格条件との対応は[出荷evidence](verification/2026-09-15-0.8-evidence.json)へ保存している。通常IPAはCounter/Reminderと汎用Share Extensionを含む。受信先Featureにはoptional `incoming`登録が必要で、診断A/B・Records・ignored Zaikoは通常IPAに含めない。

## 残る範囲と観測限界

- P1の失敗再試行は最終の重複なし/B保持を実機確認したが、失敗直後の未取込み行は独立観測なし。保持の内部条件はCI証拠と分ける。
- Widgetは上書き/Refresh後の起動で保持を確認。再登録直後の単純な強制終了だけを独立して再試験してはいない。即時更新は保証しない。
- 通常版へ戻した後に診断Widgetの旧表示がホームへ残った。通常IPAに診断kind/resourceはなく、旧表示だけからコード継続・store再読込・データ削除を判定しない。
- SimulatorのSpotlight解除で過去に120秒超過、後続で約63秒の成功があった。実機は体感ほぼ即時で成功したが、遅延原因は未確定。集中モード下の通知配信も確認済み範囲へ含めない。
- P2/P3の位置・実OS background起動・継続表示の未解決観測・外部identity・通常複数window等は未完。音声・captureは0.8.3の採用通常範囲を完了し、特殊構成や初回写真エラーの未解明観測と区別する。P単位の完了を親D全体の完了と扱わない。

## 1.0の決定と文書

1.0は未達。2026-09-15にユーザーが[Issue #6](https://github.com/y-aplus/JibunKit/issues/6)の推奨境界を採用した。P2-A全体とP2-B通常範囲、採用したP2-Cを実装/接続/検証/説明まで閉じる。操作Widget/Controlは0.8.1で完了。P2-Lは対象別実機と通常版復帰を確認し、0.8.2で公開済み。Live Bの単発の値差分は原因未特定で、実機と実4Feature保持回帰の合成評価でP2-5採用通常範囲はcompleteとする。

P単位の状態は[plan.json](delivery/plan.json)、D全体の残件は[台帳](coexistence-ledger.md)、責任は[共存原則](coexistence-boundaries.md)、版境界は[優先実装](implementation-priorities.md)が正本。過去のCI待ちや公開状態は、日付付き検証記録・履歴・過去release notesの当時の記録として読む。

0.7.0はP0全6単位を[CI/実機/公開取得で確認](verification/2026-09-13-0.7-release.md)した版。0.6.0の範囲と証拠は[当時の公開記録](verification/2026-09-12-0.6-release.md)へ保持し、新候補の結果へ読み替えない。

## 0.8.0後の開発

1.0範囲の採用に伴い、plan.json/schema2へP2の13追跡単位と7つのCI境界を追加した。P2のうち10単位は必須機能、3単位は低負荷候補/P2-Cの採否と採用範囲を扱う。単なる台帳件数を完成機能数とはしない。ローカルdelivery検査19件が成功し、通常機能の省略・条件付き未検証・長すぎるrun見積りを拒否する。

P2-WはCI35027469173（e984d44）で独立A/B/統合build、metadata10定義比較、native4件、通常管理UI1件、診断IPAが成功。通常job34979381516の共有290件（skip2）、Records11件、別process probe、通常IPA/UI13件/Files往復1件は差分を確認して再利用した。初回無効化はSimulatorで約88秒、通知終了後のSpotlight接続中断も記録されており、遅延の解消とは扱わない。

e984d44の診断IPAで一括実機確認が完了。Widget/Control各二候補・選択変更・背景からの加算、アプリ/端末再起動、同IPA上書き/SideStore Refresh、片側項目削除/無効化/全削除/再登録/選択JSON復元と古い設定拒否・B保持、通常IPA復帰が成功した。Control設定は編集状態で開く。実機の無効化はほぼ即時。本体表示も手動再読込みなしで更新されたが、一般的な即時更新保証とはしない。[操作記録](verification/2026-09-15-p2-widget-control-device.md)。

0.8.1/build11のsource88ab7cbはCI35038442208で成功。実行コードは実機確認版と同じで、製品差分は3bundle版のみ。main統合・0.8.1正式公開・IPA/ZIP無認証再取得/一致/CRCまで完了した。P2-7はcomplete。1.0全体は未完で、次はP2-LのLive Activities/AlarmKit。旧sourceのCI/実機を今回sourceへ無条件に読み替えない。[出荷照合](verification/2026-09-16-0.8.1-release.md)・[接続ガイド](guides/interactive-widgets.md)。

## 0.8.2のP2-L

Live Activities/AlarmKitの共通所有・寿命・照合、通常管理/復元接続を実装。共通326件（skip2）、Records11件、独立A/B/Combinedのapp/Widget/metadata、Live native4/Alarm native2、通常診断host管理UI1、通常/診断IPAが成功。OS開始/更新/停止・Alarm標準stop callback・片側管理/復元・通常版復帰の一括実機を確認。Live Bが上書き前に期待230ではなく200と表示された観測は原因未特定で、210からの限定再確認では再現しなかった。当時はP2-5をpartialとしたが、2026-09-18の再評価で採用通常範囲をcompleteとした。0.8.2/build12はCI35075825942と取得IPA検査が成功し、公開IPA/ZIPの再取得まで完了。実4Featureの非初期値/世代について片側管理・JSON復元後の他方保持を自動試験で確認した。[一括実機手順](verification/2026-09-16-p2-continuing-surfaces-device.md)・[source別証拠](verification/2026-09-16-p2-continuing-surfaces.md)。

## 0.8.4後の進行中検証

BLEは59f7081診断版で、新processにおけるOS復元callback経由connectedと受信値2324を実機確認した。追加の永続ログで12:56:16Zの同一復元世代Notify2バイトも確認。OS自動起動の契機は未判定。詳細は[追跡記録](verification/2026-09-18-ar-followup.md)。P2-6の実OS英語Widget/代表camera許可文言はCI35347692100で2件成功、native80件成功。採用範囲はcomplete。P2-5も実機と既存4Feature保持回帰の合成でcomplete。BLEは過去processの成功が最新表示で隠れる診断を改善し、P2-11は実OS二window復元の追加自動試験を進める。追加実機操作は要求していない。

</details>
