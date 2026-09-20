# Changelog

このプロジェクトの利用者に影響する変更を記録します。

## [1.0.0] — 2026-09-19

- The owner accepted the v1 coexistence criteria and publication on 2026-09-19 after the final document and artifact audit.
- Consolidates the verified P0/P1/P2 ownership and lifecycle APIs delivered in 0.x. Normal product code is unchanged from 0.8.5 apart from version/build metadata.
- Adds evidence for cross-process background HTTP restoration on device and terminated-process Region entry/exit on Simulator.
- Explicitly retains unobserved OS/device conditions and optional, unverified signed CloudKit/APNs integrations. See [release notes](docs/releases/release-notes-1.0.0.md).
- Reorganizes developer-facing documentation and release history for the public repository.

## [0.8.5] - 2026-09-19

- windowごとに最後に選んだFeatureを保存し、OS sessionの再接続時に復元する。無効・未登録の保存先は消去し、再導入時の意図しない再表示を防ぐ。任意の画面階層全体を自動保存する機構ではない。
- BLEの新process復元と同一世代Notifyを実機で確認し、診断に過去processの完全な復元証拠を別表示する。OS自動起動の契機や配送時刻は未判定・非保証。
- iPad Simulatorで二windowの別owner/値の終了後復元、片側破棄後の他方保持、無効保存先の消去を自動検証。実背景位置callbackと英語Widget/代表camera許可文言も確認。物理iPadの検証へ読み替えない。
- 0.8.5/build15はCI35357260854の通常版build・限定回帰が成功。通常IPA上書き後のCounter/Reminder保持と前景復帰後の表示・操作を実機確認し、同一IPAを正式公開。

## [0.8.4] - 2026-09-18

0.8.4/build14を公開。出荷CI35333186866、対象別実機と公開IPA再取得を確認。1.0は未完。

- 背景処理・位置・BLE・外部データidentity/APNs・複数windowのFeature所有/寿命とhost接続を追加。署名条件付き通信やOSのcold復元等は未確認として明示する。
- 前景ARSessionの所有・scene離脱停止、任意採用の保存専用Action extension、Feature外観/idleの接続例、通常Widgetのen/ja文言を追加。
- BLE診断ボタンの同時操作を避ける配置に修正。nativeのscan時delegate再設定と接続object置換を除去し、復元されたGATT objectの世代索引・Feature起動前の通知保留を補う。保留超過は明示失敗とする。
- 再署名後の背景登録ID整合とFeature別起動エラー処理を追加し、起動クラッシュ後に実機起動成功を確認。背景HTTPは同一processでOS callbackから保存/completionまで実測。継続処理code1の根本原因とcold配送は未確認。
- AR・Action・idle、BLE通常通信/両Feature受信/片側停止後維持/再接続を診断IPAで実機確認。iPad実機は今回見送り、実二windowはSimulatorの証拠のみ。
- 通常候補IPAで既存Counter/Reminder保持とJSON書き出し・読込を実機確認。Files自動UIの失敗は未解決として保持し、出荷CIは成功。診断Featureを通常IPAへ含めず、既存Counter/Reminderの保存IDを維持する。

## [0.8.3] - 2026-09-17

0.8.3/build13を公開。対象別CI・実機と版変更後CI35169921272、公開IPA/ZIPの無認証再取得を完了。

- AudioSessionのowner別調停、明示競合切替、停止/復旧待ち、Now Playing操作配送を追加。
- camera予約とcapture/VisionKitの寿命・同意・scene接続、音声付き撮影の共有audio hookを追加。
- 全画面提示時のhost scene誤切断を修正。実UIKit回帰と実機の文書保存/取消・QRを確認。
- 共有359件（既存skip2）、native28件、通常通知UIが成功。再生/録音・背景/OS操作/Siri・経路変更、写真/動画/文書/QR、通常版復帰を対象別実機で確認。全組合せの反復は行わない。
- 写真初回の不明エラーと旧Live Bの値差分は原因未確定として保持。通常IPAへ診断Featureを含めず、既存データIDを維持。

## [0.8.2] - 2026-09-16

0.8.2/build12を公開。CI35075825942で通常IPAと実Feature状態保持試験が成功。

- Live Activities/AlarmKitの型付きadapter、owner別journal/受付調停、再起動照合、通常管理/復元接続を追加。独立/統合CI、OS操作・標準停止callback・片側管理/復元・通常IPA復帰の実機結果を記録。診断Featureは通常IPAに含めない。
- Live Bが上書き前に期待230ではなく200と表示された観測は原因未特定。210へ更新後の再起動とAlarm Aの削除/無効化/復元では再現しなかった。保存保証の全面合格や修正済みとは扱わず、P2-5はpartialを維持する。

## [0.8.1] - 2026-09-16

- owner別process共有状態、通常管理/復元のoptional外部受付、独立A/Bの設定可能Widget・操作Control接続例とガイドを追加。native/通常回帰とOS操作・設定保持・再起動/上書き/Refresh・管理/選択復元/B保持・通常復帰を実機確認。版変更後CI35038442208、通常IPA/ZIPの公開取得も成功。通常IPAへ診断A/Bは含めない。
- Counter/Reminderの保存IDと通常Widget/Shortcutを維持。削除/復元後の古いWidget/Control操作は拒否し、対象の再選択で再開する。
- Issue #6推奨境界を1.0の正式範囲として計画へ反映。P2-W以外の採用P2範囲は継続開発する。

## [0.8.0] - 2026-09-15

- P0を維持してP1全6単位を完了し、0.8.0/build10を公開。6beb877/4e6a3f4の対象別実機証拠、製品source71ef1ffのCI/IPA検査、minor文書58件レビューと公開IPA/ZIPの再取得を確認。正式0.7.1は公開していない。
- P1-A: Feature別の共有受信先選択、永続inbox、取消・冪等再試行と管理への接続、独立PackageのIntents/静的Widgetの通常host・保存・管理への接続を追加。共有文字列のUTF/NSString限定secure archive読込みと初回保存先の検査を修正。実機で共有/Files直接入口、再試行/B保持、Shortcuts取消/失敗/回復、Widget表示/管理と更新保持を確認。
- P1-B: 通知添付の所有者別一時コピーと取消/削除時の寿命管理、停止後のlogout等を待つ`withStoppedOperation`を追加。HTTP/Web/通知の二Featureを通常入口で検証し、端末内サーバーで動く診断IPAによる実機確認も受領済み。
- 通常IPA復帰でCounter/Reminder・通常Widget/Shortcutの保持と動作を実機確認。診断Widgetの旧表示はホームに残る場合があり、コード除去と配置/データの削除を同一視しない。
- Spotlight解除の過去の120秒超過と再試行約63秒の遅延原因は未確定。実機の初回無効化は体感ほぼ即時で成功したが、Simulatorの原因特定とは扱わない。
- minor出荷時の文書全件レビューを維持し、個別理由/SHA-256の重複記録を確認Git commit・全件一覧・まとめた理由と未解決事項へ簡略化。実装・検証に伴う日常の文書同期は引き続き必要。

## [0.7.0] - 2026-09-13

- P0-AでFeatureの開始・停止・再開、通常保存と排他保守、終了進捗を通常hostへ接続し、P0-BでFeature所有の提示、利用同意、無効化・再有効化、登録と所有データの削除・失敗再試行を追加。非実機条件は通常・生成CIで検証済み。0.7.0候補の一括実機も確認済み。
- P0-CでSwift Package追加時のpath/product/target依存/Registry診断と、二Packageの片側互換更新・復旧手順を追加。0.7.0 build8候補のCI34705653297・実機・配布整合性は確認済み。
- Issue #5に基づきP0完了を0.7.0、P0を維持したP1完了を0.8.0に設定。P0-5のアプリ内無効化・削除UIを必須化し、1.0の最終対応範囲は需要調査後の判断へ保留。
- CI境界を5つの大きなまとまりに固定し、CI前の契約・一括レビュー・run予算・再実行手順を導入。計画/証拠/文書確認のローカル検査ツールを追加。
- minor更新ごとに現在状態を示す文章を全件確認・更新し、公開候補と公開後の状態を同期する運用を必須化。

- 同名の純Swift SDK moduleを標準moduleAliasesで分離する比較と接続手順を追加。iOSではPackageの公開product名を分けた構成で両版/設定と片側更新後の他方保持を検証。元の同名product構成はXcodeの依存グラフで失敗し、manifest編集が必要な条件を明記。
- shared background refreshの実機用診断fixtureを追加。iOS注入試験とapp/UI targetのコンパイルまで確認し、実OSの受付・起動・期限は未検証として保持。
- 現在状態の文書を0.6.0公開後のmainへ同期し、初期棚卸し・旧計画を履歴資料へ分離。停止時の記録を保持し、2026-09-12の明示再開後の状態を反映。

## [0.6.0] - 2026-09-12

- 複数Featureのbackground refresh要求を一つのOS枠へ調停する明示APIを追加。owner/local ID別の永続保存、世代別の復旧、期限通知と全処理完了待ちを接続。実OSによる受付・起動の保証とは分ける。
- app/Widgetで標準のmixed localizationを有効にし、Package固有の翻訳をホストの対応言語へ制限しない。生成ホストで英語・日本語・ホストにないフランス語と二Packageの独立した値を検証。
- Swift Packageの静的Widgetを標準WidgetBundleへ組み込む接続を検証。単独/統合版のgallery、ホームへの追加、App Group経由の実値表示、片方の更新後の他方保持を確認。
- 長いミニアプリ一覧のUI試験が画面外の遅延生成行を探せず失敗する問題を修正。

## [0.5.0] - 2026-09-11

- 添付付きZIPバックアップも日付入りの保存名を実ファイルと転送候補へ渡し、固定名による上書き・改名の手間を防ぐ。

- Feature間のAppEntity/queryの名前衝突を標準の永続識別子で避ける手順とnative比較を追加。統合で消えたIntent/entity/queryや誤った参照を、単独版metadataと照合する検査ツールを提供。

- MiniAppDefinitionへ任意のonHostLaunchを追加。画面生成に依存することなく、host起動時にFeatureのnative登録処理を呼び出す。

- Background URLSessionのFeature/profile別識別子とhostイベント再接続を追加。登録解除と進行中イベントの終了を分け、重複・遅延・再入でも各OS completionを一度だけ呼ぶ。

- 通常CounterのShortcut定義をFeature側へ移し、既存の公開IntentとProvider識別子・引数・文言を保持したままhostへ合成する。

- BackgroundTasksの登録・pending取消・実行中処理をFeatureごとに所有するAPIを追加。処理ごとの通信/電源条件を保持し、期限通知と完了を重複させず、完了まで処理を保持する。

- Feature所有の標準Swift App Shortcut式を、一つのhost Providerへ合成するTuist helperを追加。単独/統合metadataの一致と、一方の寄与削除後の他方保持を検証。

- Keychainに標準SecAccessControlと操作ごとのLAContextを渡せるようにし、既存itemの保護とFeature別の取得・削除範囲を維持。実機で認証なしの読取/更新拒否と、認証後の元の値・別Featureの値の保持を確認。

- FeatureをNavigationStackのrootに置き、別Featureから詳細URLで開く際に遷移先の登録が無視される問題を修正。Feature固有のpathは詳細値だけを持ち、rootの「ミニアプリ」ボタンで一覧へ戻る。

- Web認証の提示面ごとの任意調停とFeature接続別の取消・Runtime終了処理を追加。標準ASWebAuthenticationSessionのcallback形式と提示先を維持する。
- Swift Package内のApp Intentsを標準AppIntentsPackageで接続する手順と、単独/統合metadata・所有Storeの比較検証を追加。

- Featureごとの独自URL resolverを追加。曖昧な受信先を拒否し、SwiftUIが配送したscene内で所有Featureを開き、他Featureの画面経路を保持する。
- Featureの`CFBundleURLTypes`をhostと自動合成。宣言のname/role/icon等を保持し、同名異値だけ明示resolutionを求める。

## [0.4.0] - 2026-09-11

- 通知action/foregroundの所有Featureへ、元のnative requestを復元できるsnapshotを渡す。独自userInfoやcontent/triggerを保持し、既存ハンドラーの互換性を維持する。実通知で所有者別配送と他Feature表示維持を検証。

- Featureとhostの言語別InfoPlist.stringsを合成し、app/Widgetへ別々に組み込む。言語・keyごとの衝突を明示解決でき、削除済み設定は次回生成で除去する。CIは固定文言でなく、各targetの生成設定と実bundleの一致を確認する。

- UIKitの短時間バックグラウンド実行tokenをFeature/処理ごとに所有し、個別完了・期限切れ・Runtime終了・解放時に終了するAPIを追加。他Featureのtokenを維持し、重複終了を防ぐ。OSの実行時間枠はhost全体で共有する。

- Core SpotlightのFeature別item/domain識別子と所有者限定削除を追加。native属性を保持し、Aの削除後もBの検索結果が残ることを署名付きiOS hostで検証。検索結果から所有Featureの詳細へ配送し、別Featureの経路を保持。host終了後の検索結果からの起動も検証した。
- FeatureのInfo.plist/entitlements要求をTuistで合成する仕組みを追加。異なる値の衝突を検出し、明示resolutionと限定した文字列集合の合成を提供。IPA署名もTuistの生成entitlementsを使う。

- 通常の保存操作を共有バックアップと調停する`withStoreAccess`を追加。同じFeatureの通常アクセスは並行でき、処理中の復元/snapshotと、復元中の新規アクセスを拒否する。他Featureは継続し、画面はデータ使用中を案内する。

- 復元前の停止が途中で失敗した場合の任意の回復callbackを追加。回復完了まで重複処理を拒否し、未復元と回復失敗を画面で区別する。SQLiteの実BUSY close、他owner保持、既存を含む6失敗経路で検証。

- 選択中かつactiveなsceneがある間だけ自動ロックを防ぐ任意の要求scopeを追加。非選択・背景化で解除し、復帰時に再適用。別ownerの明示leaseと複数sceneを維持し、Runtime終了後の再取得を拒否する。
- Records参照アプリで、行の文字列横の空白も詳細表示へのタップ対象に修正。

- Featureごとにsceneの活動状態・選択状態・接続終了を受け取る任意callbackを追加。既存のhost集約通知を維持し、非選択を自動的な処理終了へ変換しない。iOSの切替・背景化/復帰・他FeatureのTask継続で検証。

- 同じscene内のミニアプリ切替で、各Featureの値ベースの画面経路を保持。下部の切替メニュー、一覧からの再開、選択中だけのroot resetを追加。既存root URL/通知の動作は維持し、他Featureの経路を消さない。

- Feature/RuntimeごとのFoundation NotificationCenter購読を追加。owner限定取消、個別token取消、queued MainActor配送の抑止、購読解除とcapture解放を提供。実Foundationの9テストとiOSビルドで検証済み。並行取消とRuntime終了の保証は[接続ガイド](docs/guides/owned-notification-observations.md)を参照。

## [0.3.0] - 2026-09-10

- Feature/profile別Keychain・Cookie・HTTPパスワード資格情報の明示保存とnative URLCacheを追加。実HTTPとiOS process再起動で所有者分離を検証。
- MiniAppRuntimeの受付停止・Task取消/完了待ち・同期/非同期資源解放と、native URLSessionの終了待ちを追加。
- 選択復元のstop/apply/resume・重複予約・snapshot調停・取消/失敗段階の報告を追加。
- 通知カテゴリ合成・動的更新・owner限定削除・foreground方針・custom action配送を追加。
- host活動状態配送、idle timer lease、Feature/profile別WKWebsiteDataStore割当を追加。
- singletonのNavigationPathを廃止し、window別の状態所有とprocess通知の一件配送へ変更。
- 配布版の本体/Widgetを0.3.0 build 4へ統一。1.0は引き続き未達。

公開状態・検証範囲・既知の不足は[0.3公開記録](docs/verification/2026-09-10-0.3-release.md)を参照。

## [0.2.0] - 2026-09-09

### Added

- 添付ファイルを含むZIPバックアップ、Featureごとの選択復元、schema移行と破損時のデータ維持を追加。書出し名へ日時を含める。
- Core非依存のRecords参照Featureに、複数画面・構造化保存・添付・検索・UUID詳細ルート・記録別通知を実装。通常配布への自動追加は行わない。
- Feature所有の詳細識別子をURL・通知payloadからIntegrationへ渡す接続と、安定キーごとの複数通知IDを追加。

- 対応ミニアプリを選んでバックアップを書出し・読込み・復元する画面を追加。全選択の事前検証と上書き確認、部分失敗の報告を行う。

- FeatureごとのApp Group内ファイル保存先を提供する`MiniAppFiles`を追加。任意のデータ形式・DBで使えるURLと、Dataのファイル単位のatomic書込みを提供。

- 独立Swift Package・Root View・単独Example・UIテストを生成するTuist Feature雛形を追加。ホストへはIntegrationを明示登録する。

- GitHub Actionsで任意実行できるiOSシミュレーターの統合操作テストと、画面・実行記録の成果物を追加。

### Changed

- iOS project生成をTuistへ移行。xtool・Ruby後加工と独自Python生成を廃止し、独立Swift Package／単独appのTuist templateを追加。Counter／Reminderのホスト定義をIntegration targetへ分離。

- ミニアプリのID、表示情報、遷移先を1件のDescriptorへ統合し、通常の追加でホストのID enumや画面遷移switchを編集しない登録方式へ変更。
- Featureへ安定した保存・通知namespaceを渡す`MiniAppContext`を追加し、独立アプリの`@main`をFeatureから分離する組み込み境界を明文化。
- カウンターとリマインダーのRoot View・保存処理・通知予約をFeature側へ移し、`MiniAppContext`から保存キーと通知情報を取得する基準実装へ変更。保存キーと通知先は従来通り。
- ミニアプリの定義(ID・表示名・アイコン・Root View)をFeature側が所有する`MiniAppDefinition`へまとめ、Registryは定義の列挙だけにする。App Group解決は`MiniAppStorage`へ集約し、ID・保存namespace・通知IDの事前検査を`MiniAppValidator`で行う。
- 1.0の目標候補を、ソースコードがある独立Swift／SwiftUIアプリからFeatureライブラリと薄いAdapterへの分離支援として明確化。

### Fixed

- 通知タップ後にOSへ完了を返すdelegate処理をメインactorへ固定し、UIKitの状態復元処理が別スレッドで動いてクラッシュする問題を修正。
- Storeごとのactorだけに依存していたカウンター加算を、JibunKitCoreの共通排他処理へ接続。画面とShortcutsなど複数Storeの同時加算による更新喪失を防止。
- ドットを含むミニアプリIDの保存namespace・通知IDをエスケープし、他Featureのキーや通知prefixとの衝突を防止。既存3アプリのキーは維持。ドット入りIDを使用した派生の移行方法は`docs/updating.md`を参照。
- macOSでのFeatureテストの最低OS条件と、iOS通知取消しのコレクション型を修正。

## [0.1.0] - 2026-09-04

### Changed

- 製品名をJibunKitへ変更し、本体・Widget・App Groupの技術識別子も中立なJibunKit名へ統一。

### Added

- ミニアプリ一覧、共有保存を使うカウンター、独立保存を使うリマインダー。
- App Shortcutsから数値を加算し、更新値を返すApp Intent。
- 3サイズの表示専用Widget。
- 許可操作、予約、foreground表示、通知タップからの遷移を扱うローカル通知。
- WSLでのローカル確認、GitHub ActionsのXcode 26.6によるIPA生成、SideStore導入・更新の文書。
- ミニアプリ追加、基盤更新、貢献、脆弱性報告、公開・releaseの手順。

### Verified

- iPhone 16e、iOS 26.6、SideStore 0.6.3で、JibunKitの初回導入、build 2への上書き、署名更新後の保存値・Shortcuts・Widget・通知を確認。
- クリーンなGitHub-hosted macOS runnerで、全テスト、App Intentsメタデータ、本体・Widget、署名構造、IPA整合性を確認。

### Security

- GitHub Actionsの外部actionを固定commitへ変更し、checkout credentialを保持しないようにした。
- credential、署名・pairing材料、Apple SDK、IPAを追跡しない公開境界チェックを追加した。

### Fixed

- App Shortcutからの加算が整数範囲を超える場合、processを停止せず保存値を維持してerrorを返すようにした。

[Unreleased]: https://github.com/y-aplus/JibunKit/compare/0.7.0...HEAD
[0.3.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.3.0
[0.2.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.2.0
[0.1.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.1.0

[0.6.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.6.0
[0.5.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.5.0
[0.4.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.4.0

[0.7.0]: https://github.com/y-aplus/JibunKit/releases/tag/0.7.0
