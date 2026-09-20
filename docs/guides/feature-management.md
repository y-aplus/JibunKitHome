# Feature management integration

## Current integration contract

Management actions operate through the same feature coordinator as normal runtime work. Enable, disable, restore, reset, and remove must be serialized with startup and shutdown, close admission before destructive maintenance, and surface partial failure for retry.

The host may present management UI, but feature code owns its data model, consent declarations, external registrations, and removal implementation. Management must not infer success from a hidden screen or a stopped runtime, and must not affect another owner.

Register a matching lifetime and removal provider on `MiniAppDefinition`. A data-free/read-only feature still declares that fact with a no-op provider; omission does not mean no data. Put host-unmanaged external registrations in `onUnregister`. Deregistration and removal must be idempotent because partial progress is not rolled back: persist an incomplete state, distinguish an in-flight callback from a returned error, retry after process death, and block re-enable until completion. Default-index Spotlight domains are automatic; custom indexes belong in `onUnregister`.

Disable/remove first rejects new starts, then joins owned runtime work before touching registrations or data. Long-running UI work registers with the runtime. Management runs outside owned tasks to avoid self-wait. Use the same `MiniAppRestoreCoordinator` for normal access, backup, maintenance, and management; stale screens must pass through it and providers already under reservation must not reacquire it.

Use `onHostLaunch` only for synchronous native registration required during cold launch; callback business work still passes through `lifetime.start`. Re-enable restores admission/static registration but does not request OS permission or start business work. Declare stable permission IDs, user-facing purpose, and denied behavior; read feature consent before requesting app-wide OS permission. Re-registration resets feature consent to unconfirmed.

Persist management status in the existing App Group when configured. Widgets hide disabled/removing/removed owners and request a timeline refresh without promising immediate display. Shortcuts and other process writers initialize status on cold launch, check admission, and use store coordination; a one-time status read is not a write lock. Optional cross-process writers use `Definition.externalAccess` and must participate in stop/remove/restore coordination.

## Japanese source notes and historical evidence

0.8.1以降の別process writerは、optionalのDefinition.externalAccessを使う。[操作Widget/Controlのガイド](interactive-widgets.md)に起動・停止・削除・復元との契約を記す。0.8.0以前には未収録で、新接続のnative/通常管理UIは35027469173で成功。実OS Widget/Controlからの更新拒否・片側削除/再登録・復元・B保持もe984d44で実機確認済み。版更新後CIと0.8.1公開IPA取得も完了した。

P0-Bで通常hostへ接続し、通常・生成CIの非実機条件を確認済み。対象sourceと試験範囲は[検証記録](../verification/2026-09-12-p0-b.md)を参照する。0.7.0候補の実機確認も2026-09-13に完了（[結果](../verification/2026-09-13-0.7-device-check.md)）。

MiniAppDefinitionにFeatureと同じidのlifetimeとremovalを渡す。removalは削除するデータを説明し、owner予約済み・Runtime終了済みの状態で所有データだけを削除する。読み取り専用で所有データがない場合は、その説明と何もしないcallbackを明示する。providerの省略を「データがない」と解釈しない。

hostが管理する通知/category/Spotlight以外の所有登録はonUnregisterで解除する。登録解除とデータ削除callbackは部分失敗後に再実行できるようにする。途中で削除したデータが自動rollbackされるとは約束しない。取消/失敗は管理状態に残り、再試行で残りを完了する。

Spotlightの自動解除はdefault indexのowner domainが対象で、custom indexはonUnregisterへ接続する。非同期callbackがまだ返っていない状態と、エラーが返って操作を終えた状態は異なる。前者は登録解除中、後者は未完了状態と再試行操作になる。操作途中でprocessが終了した場合も未完了状態を保存し、再起動後は無効化または削除の再試行を行う。完了前に再有効化はできない。0.8候補のSpotlight応答待ちの未解決事象は[検証記録](../verification/2026-09-14-p1-b.md)を参照する。

画面ボタンから長引く処理を開始する場合は環境値miniAppLifetimeのRuntimeへ登録する。通常の画面切替はRuntimeを終了しない。無効化/削除は新規起動を拒否し、所有処理の終了を待ってから登録とデータへ進む。Runtime自身の所有taskからstopや管理操作をawaitすると自身の終了待ちになるため、管理は外側のhostから行う。

MiniAppRestoreCoordinatorを通常アクセス・バックアップ・保守・管理で共有する。無効なownerの新規アクセスを拒否するので、古い画面が保持するproviderも同じ予約入口を通す。provider内部は予約を再取得しない。既に受け付けた操作との競合は管理の未完了状態として再試行する。独自coordinatorや直接のファイルアクセスへ迂回するコードを強制的に止める機構ではない。

onHostLaunchはOSがcold launch時に要求する同期登録用である。登録されたcallbackからの業務処理はlifetime.startの受付を通す。無効Featureだからとnative登録の必要時刻を遅らせない。再有効化ボタンは受付と静的登録を戻すだけで、OS権限要求や業務処理を開始しない。

権限はpermissionsで安定したid・タイトル・目的・拒否時動作を宣言する。環境値miniAppConsentStoreからowner別の同意を読み、未確認の場合は操作の前に説明、拒否の場合は宣言した代替動作へ進む。OS側の権限確認/要求はその後に行う。通常Reminderがこの接続例であり、standaloneではhost同意storeがない場合のOS権限処理を維持する。Featureの利用同意とiOSがJibunKitに付与する権限は別で、同一process内の強制セキュリティ境界ではない。

削除後の再登録では同意を未確認に戻す。バックアップは現在の有効な対象を一覧化し、削除したownerのsnapshot/restoreも共通予約で拒否する。

通常hostは管理状態を既存App Groupのdefaultsへ保存し、Counter Widgetも同じ領域からMiniAppManagement.savedStatusを読む。無効/削除中/削除済みの値を表示せず、hostは状態変更時にtimeline更新を要求する。更新時刻はWidgetKitの調停に従い、即時の画面変更を保証しない。共有設定が解決できないhostではlocal管理を維持し、Widgetは共有領域を読めない表示となる。
通常Counter Shortcutはcold launchでもhost管理状態を初期化して受付を確認し、共通保存予約内で更新する。別processのwriterを追加するFeatureはsavedStatusの一回の読取りを排他制御と扱わず、対象processとの終了/書込み調停も接続する。画面から隠したことだけで停止済みと扱わない。
