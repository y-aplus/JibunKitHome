# Interactive widgets, controls, and feature state

## Current integration contract

Widgets and controls run in a separate process and must not reach into a live `MiniAppRuntime`. They read a small, versioned snapshot and submit intent through an App Intent or durable command boundary. The main application remains the authority for business state, ownership checks, migration, and conflict resolution.

Use an App Group only when the host has configured and signed it. Serialize writes, make commands idempotent, and refresh timelines after committed changes. Removing or disabling a feature must also remove or reject its outstanding widget commands. Build and metadata evidence does not replace device verification.

Use stable owner-specific entity IDs that include the saved-data generation and item lifetime. A deleted or restored item is not replaced by the first current item, and recreating the same local ID does not let an old control mutate new data. Keep widget/control `kind` as a `nonisolated static let`; do not move a whole intent to `MainActor` merely because display types are isolated.

For small Codable state, all processes use `MiniAppSharedState<Value>` in the same App Group. Pass the generation returned by `read()` into `update(generation:)`; its synchronous closure reads, mutates, and writes under one file coordination. Updates, deletion, and management stop share that coordinator, while owners remain independent. Do not fall back to `.standard` defaults when the App Group is unavailable.

Pass `Definition.externalAccess` (or `effectiveExternalAccess` when continuing surfaces are composed) to management. Startup `prepare` reconciles saved management state and initializes only new registrations; an incomplete restore leaves that owner stopped with a visible reason while other owners continue. Restore prepares and validates a value, then uses `replaceForRestore` under `effectiveRestoreLifecycle`; providers do not reacquire the outer coordinator reservation.

User configuration must explicitly select a surviving entity after deletion/restore. A widget reload is a request, not proof of immediate rendering. Intent execution rechecks saved management status and generation at commit time, reports rejection/failure, and preserves other owners. Validate metadata, direct intents, cross-process behavior, system UI operation, restart, management, restore, and upgrade as distinct layers.

## Japanese source notes and historical evidence

0.8.1以降向け（2026-09-16更新）。0.8.0以前には未収録。共有状態9件・管理接続8件・macOS別process probeと通常版回帰は成功済み。e984d44の独立/統合native build・metadata比較・直接Intent4件・通常管理UI1件も成功。e984d44の一括実機でOS Widget/Control操作・設定保持・再起動/上書き/Refresh・管理/復元とB保持・通常復帰も確認済み。0.8.1の版変更後CI/公開IPA取得も完了。[検証記録](../verification/2026-09-15-p2-widget-control.md)を合否の正本とする。

## 標準APIと責任

FeatureのSwift PackageがAppEntity/EntityQuery、WidgetConfigurationIntent、ControlConfigurationIntent、操作AppIntent、Widget/Controlの型と永続識別子を所有する。本体とWidget extensionが同じPackageを依存へ加え、AppIntentsPackage.includedPackagesとWidgetBundleへ登録する。metadataはXcodeが生成し、JibunKit側で書き換えない。

`Tests/InteractiveWidgets/FeatureA`と`FeatureB`は独立した接続例である。二ownerがそれぞれ`same-id`と`second-id`を持つ。候補はそのownerの現在の項目だけを返す。選択entityのIDで対象を決め、削除済み設定を先頭項目へ自動置換しない。entity IDには保存世代と項目の生存期間を含め、削除・復元後に同じlocal IDを作っても古いボタンが新データを変更しない。復元後には対象の再選択が必要になる。

操作Intentは本体を開かず共有領域を更新できる。WidgetはAppIntentConfiguration/AppIntentTimelineProviderとButton(intent:)、ControlはAppIntentControlConfiguration/ControlWidgetButtonを使う。既存Counter/静的WidgetのIDは変更しない。OSがIntentをどのprocessで動かすか調停するため、本体のシングルトンだけを前提にしない。

Widget/Control型のkindは背景Intentからも参照する不変のStringなので、`nonisolated static let`で宣言する。表示型のMainActor隔離を更新処理へ持ち込むために、Intent全体をMainActorへ移す必要はない。

## 小さなCodable状態を共有する場合

`MiniAppSharedState<Value>`はowner別のApp Group領域を使う。全processが同じ保存実装を通すことが前提である。`read()`の世代を`update(generation:)`へ渡し、同期closure内で読込み・変更・保存を一つのファイル調停として行う。更新・削除・管理停止も同じ調停先へ直列化する。異なるownerの調停先は独立している。

更新closureからasync処理、同じstoreへの再入、rollbackされると期待した外部副作用を行わない。throws/取消/エンコード失敗では未commitの変更を保存しない。破損・不明owner・欠損をWidget側で初期値に置き換えない。共有設定が利用不能なら、標準defaultsへfallbackして別データを操作しない。

既存DBや大きなファイルの移行を強制するAPIではない。独自DBはtransaction/connection/process coordinationを維持し、externalAccessを同じ保存責任へ接続する。協調APIを迂回するコードの強制隔離や同一processのクラッシュ分離は提供しない。

## 通常管理・復元への接続

```swift
let state = try MiniAppSharedState<MyState>.shared(owner: owner)
let definition = MiniAppDefinition(
    id: owner, title: "My app", systemImage: "square",
    backup: provider,
    removal: .init(id: owner, dataDescription: "My appの全項目") {
        try state.remove()
    },
    externalAccess: state.externalAccess(initialValue: initialState)
) { context in MyRoot(context: context) }
```

0.8.1のhostはDefinition.externalAccessを通常MiniAppManagementへ渡す。0.8.2開発中のhostは継続活動との合成を含む`effectiveExternalAccess`を渡す（継続活動がなければ同じadapter）。起動時prepareは保存済み管理状態と整合させ、新規登録だけを初期化する。未完了の復元等を見つけたら、そのownerを停止未完了として扱い、管理画面へ失敗理由を示す。ほかのownerは初期化を続ける。

無効化/削除は外部受付を閉じ、既に受け付けた同期書込みの終了を待ってから所有処理の停止・予約・登録解除・必要なデータ削除へ進む。close失敗時は削除を始めず、成功と表示しない。削除はtombstoneを残し、seedや古い操作による復活を防ぐ。明示的な再登録では初期データと新しい世代になる。通常の無効化/再有効化では値を保持する。

バックアップproviderのprepareは検証済みValueを保持し、applyで`replaceForRestore(value)`を呼ぶ。通常hostは`definition.effectiveRestoreLifecycle`を使い、Feature固有の停止/回復/再開を外部受付の一時停止で囲む。独立hostも同じeffective lifecycleを復元planへ渡す。provider内部でcoordinator予約を再取得しない。

復元の一時停止と管理の有効/無効は別の永続状態である。復元中に管理が無効化を始めても、復元resumeは管理の無効化を打ち消さない。停止・適用に失敗して元runtimeへ戻せた場合は自分の復元予約だけを解放する。resume/recovery失敗時は閉じたままとし、明示的な無効化完了→再有効化で回復する。再有効化はhostの排他予約下で行い、生きた復元を途中解除しない。破損した保存内容をこの回復で初期化しない。

独自MiniAppExternalAccessのprepare/close/openとrestoreLifecycleにも同じ契約を実装する。NSLockやsavedStatusの一回の読取りはprocess間の予約ではない。prepareはhost起動前の同期処理なので短く保ち、長い外部通信を入れない。

## 利用者によるControl設定

コントロールセンターへ追加した後、左上の＋で編集状態に入ってからControlの設定を開き、項目を選ぶ。通常状態の長押しだけでは設定画面は開かなかった。今回の診断A/Bで編集状態から項目を選べることを実機確認した。未選択時の「利用不可」は保存失敗の断定ではない。削除/復元後は古い世代を自動的に新データへ結び直さず、利用者が対象を再選択する。

## 表示更新と検証

書込み後はWidget kindへreloadTimelines、Control kindへreloadControlsを要求する。通常管理は全登録surfaceの更新を要求する。要求とOS描画完了は別なので即時表示を保証しない。本体はscene復帰時に共有状態を再読込みする。保存値・設定entity・OS表示を別々に確認する。

native XCTestの直接performや設定型の成功は、ホーム画面/Control Centerの実操作成功ではない。独立/統合metadata、本体とextensionの依存、別process試験、通常管理UIが通った候補で、設定変更・背景操作・再起動・削除/復元・B保持・通常版復帰をまとめて実機確認する。

Appleの参照: [設定可能Widget](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)、[Widgetの操作](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)、[Controlの構成](https://developer.apple.com/documentation/widgetkit/adding-refinements-and-configuration-to-controls)。
