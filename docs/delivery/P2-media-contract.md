# P2-C: 撮影・音声の所有と中断復帰

> 履歴注記: 本文はP2-C開始時の契約・レビュー条件を保持する。音声・撮影/scanの採用通常範囲は後段で実装・検証済みであり、当時の予定や未確認を現在の待機指示として読まない。[plan.json](plan.json)と[status](../status.md)を優先する。

2026-09-16開始。公開0.8.2後のbaselineは52a29ff。対象はP2-1（AudioSession/Now Playing）とP2-2（撮影/文書・コードscan）。次の実機確認のまとまりで0.8.xを進める。P2-Lの実装/非実機/対象別OS証拠を再利用できるが、Live Bの単発差分とP2-5 partialは取り消さない。この差分に依存しない撮影/音声の設計は並行して進める。

## 共通責任と作業分担

Featureはplayer/recorder/capture session、native構成と業務データを所有する。JibunKitは一つのプロセスへ統合して失われる所有者別の受付・調停・取消・解放・配送を補う。すべてを一つの固定playerやcapture画面へ移植させず、AVFoundation/VisionKit/MediaPlayerの標準型と構成の自由度を保つ。

既存MiniAppID、MiniAppFeatureLifetime/Runtime、MiniAppPresentationOwner、scene activity、permissions/Feature consentを使う。新規APIはoptionalとし、既存Counter/Reminderの振舞いを変えない。OS許可はapp全体であり、Feature単位の利用同意・利用受付と区別する。

- 音声: AudioSessionのプロセス共有構成、互換要求の共存、非互換要求の理由付き競合/明示切替、停止の完了待ち、OS中断/経路変更/復帰を扱う。無条件全排他やcategory setterだけで完成としない。Now Playingは標準MPNowPlayingSessionが適合する範囲を使い、操作対象と停止後の配送を分離する。ユーザー停止を復帰イベントで勝手に再開しない。
- 撮影: 可視性/scene/Feature停止とnative captureの寿命を接続する。cameraとmicrophone等の要求資源を区別し、片側の取消で別Featureの処理を止めない。対応端末・OSの制約とJibunKit未実装を区別する。写真・文書scan・code scanの通常経路を含める。
- 共有接点: 音声付き撮影はAudioSession調停を迂回しない。ただし設計段階で互いの未確定APIを作り込まない。native SDK objectのactor跨ぎを避け、factory/callbackのisolationを型に残す。Swift6 compile未確認を隠さない。

親は共通契約、必要なhost/Definition/lifecycle接点、Package/Project/CI/Tools、統合と出荷を所有する。音声担当はSources/JibunKitCore/Audio/、Tests/JibunKitCoreTests/Audio/、Tests/MediaAudio/、docs/guides/audio.md。撮影担当はSources/JibunKitCore/Capture/、Tests/JibunKitCoreTests/Capture/、Tests/MediaCapture/、docs/guides/capture.md。初回はそれぞれ専用の設計提案文書だけを提出し、親が共通接点を一度揃えてから実装を並列依頼する。子はCIを実行しない。

## 検証境界

初回予算は計画済み3run以内。個別APIや担当ごとにCIを出さず、両担当の実装・試験・fixture・契約を一括レビューした後に統合境界を固定する。正確な入力/filter・実行レーン・再利用証拠・30分以内の所要見込みは実装が揃ってから投入前に確定する。3回失敗以内に原因を切り分ける。

自動試験は互換/非互換要求、片側取消・失敗、古いcallback拒否、解放順序、再開条件、他ownerの非初期値/世代保持を担当する。モデル試験に加えて実Feature接続を代表構成で検査し、同じ管理/バックアップ機構の全組合せを実機へ戻さない。

実機は新しいOS動作に限定する。音声は実録音/再生、背景・OS中断/経路変更、Now Playing操作配送の代表例。撮影は許可・実camera/scan・取消と解放、Feature切替時の代表的な資源保持。各ケースの必要性と観測方法をfixture実装時に確定し、モバイルで判定できないstatus表示を放置しない。版番号/試験/docだけの変更で成功済み実機を繰り返さない。

## 初回設計提出の完了条件

Apple一次資料と現在のSDK宣言を確認し、最小の公開API候補（Swift宣言）、actor/SDK所有、状態遷移、既存hostとの接点、失敗/競合時の振舞い、2Featureの具体例、自動/実機の分担を1文書にまとめる。要求していない機能を複雑さだけで除外しない。実装が必要なOS差分と、独立アプリでも受ける制約を分ける。未確定の共通接点は相手レーンへ要求として列挙し、共有ファイルやCIを変更しない。設計文書をcommitしたら終了し、監視やpollをせず親への一回の完了通知で引き渡す。

## 設計レビュー後の実装契約（2026-09-16）

音声・撮影の設計提出を採用するが、以下は提案より優先する。設計文書は設計時の記録であり、未検証の実装成立や出荷完了の証拠ではない。

- 対象iOSは26以上。古い録音許可APIのfallbackは追加しない。background audioは`UIBackgroundModes`の`audio`であり、一般的な専用entitlementと記述しない。usage descriptionsとbackground modesは既存`FeatureBuildRequirement`を使い、親が診断hostに合成する。
- `MiniAppDefinition`へ専用propertyを増やさず、Feature factoryが共有coordinatorを注入され、既存lifetimeの`configure`/`onShutdownAsync`と`onSceneActivityChange`に接続する。scene集約はcapture owner内。共有coordinatorはnative defaultをプロセス内で共用し、テストでは独立driverを注入できる。複数native coordinatorによるsingleton設定競合をAPI上で推奨しない。
- 音声coordinatorはrequest/profile/lease/stopの責任を持つ。互換profileの積集合は明示された許容構成のみ。純粋な調停と試験はFoundation上でも動く値型・driverに分け、SDK型のためだけの`@unchecked Sendable`を使わない。native adapterでAVAudioSession標準構成へ変換する。
- 非同期stop中も新規acquire/releaseを直列化または世代再検査し、古い競合承認で新しいownerを停止しない。stop失敗時は新requestを開始しないが、既に止めた他ownerを「動作を維持」と偽らない。実際の部分停止と復旧不能な状態を返す。releaseもnative producer停止をjoinする。coordinatorのstop callbackから同じleaseのreleaseを再帰awaitしない。
- interruption終了は再開候補の通知。Featureがユーザー停止・pause・経路抜去後の意図を更新する実APIを持ち、許可ヒントだけで自動再生しない。Now Playingの同期handlerから無条件の`MainActor.assumeIsolated`を使わず、SDK eventをその場で値に変換し、登録token/世代と実操作の配送を保護する。enqueue成功と操作完了を区別する。
- captureのcamera競合をOSのエラーだけに委ねない。プロセス共用のcapture coordinatorが同じcamera資源の競合を理由付きで返し、明示切替では旧producer停止を待つ。通常camera利用とFeature内部のMultiCam構成を区別し、後者を固定単眼構成に落とさない。microphoneはcamera mutexへ混ぜず音声coordinatorで調停する。異なる資源を無条件排他にしない。
- CaptureとAudioの接続はcapture operationの型付きhookで固定する: `acquireAudio: (@MainActor @Sendable () async throws -> (@MainActor @Sendable () async -> Void))?`。返値は取得したleaseだけの解放。camera確保後/native開始前に呼び、失敗時camera予約を返す。camera-onlyはnil、microphone要求にnilは構成エラー。親の音声付き撮影fixtureがaudio coordinatorを呼ぶclosureを提供する。音声側からのstop callbackはnative producer停止までを行い、この解放closureを再帰呼出ししない。
- native capture停止→presentation dismiss完了→関連lease解放をawaitする。許可要求中の停止、presentation失敗、開始取消でも部分取得資源を返す。inactive/background/非選択は通常captureの停止条件だが、activeな別sceneを維持する。明示的なユーザー終端を復帰イベントで取り消さない。

各担当は担当path内にcore実装、fake-driver回帰、iOS native adapter、実Feature fixture（Audioは`MediaAudioProbe.definitions`、Captureは`MediaCaptureProbe.definitions`）をまとめて提出する。fixtureは`Tests/MediaAudio/`、`Tests/MediaCapture/`内に置き、親が一つの診断hostへコピーして接続する。native XCTestはそれぞれ`MediaAudioNativeTests.swift`、`MediaCaptureNativeTests.swift`。実機の成功/停止/競合/所有者/件数がモバイル1画面で判定できる表示にする。独立アプリとの差分を見る必要のあるnative構成はfixture内で直接APIとmanaged APIを比較する。

担当は共有Package/Project/registry/CIを編集しない。親は両laneの共有契約、host生成、iOS試験実行、permission/build宣言を統合する。ローカルで可能な検証を行い、実行できないiOS buildは未確認と記録する。両提出後の統合レビューまでCIは投入しない。今回の自動試験移管は承認済みだが、版更新を実機前へ移す提案は採用済みと扱わない。
