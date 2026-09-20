# Notification attachment sources and temporary copies

## Current integration contract

Keep the feature-owned original in its storage namespace and create a bounded temporary copy for the notification request. The notification coordinator owns staging, request submission, cleanup, and recovery. Do not delete the original merely because a request completed, and do not retain temporary copies indefinitely.

Validate ownership, file type, size, and lifetime before submission. Cancellation, replacement, shutdown, and feature removal must clean up only their own staged files. Fixture success does not prove device delivery or attachment rendering.

Create an owner/operation-specific copy under `Library/Caches/JibunKit/NotificationAttachments`, then build the normal native request with that copy. Await both copying and native registration before completing the operation; do not spawn un-awaited file work. Cancellation waits for an active copy, while cancellation observed after successful native registration does not retroactively change success. Each operation uses its own directory even when file names match.

On normal completion, error, or cancellation, remove only that operation directory. `removeStagingFiles()` may clean leftovers after the owner's work drains; it preserves other owners and never deletes the feature original or the OS-managed attachment. To remove an attachment already handed to the OS, remove its pending/delivered notification request. Access a returned attachment URL under its security scope.

Management removal order is runtime drain, owner notification deregistration, staging cleanup, then business-data removal. The diagnostic fixture reads back pending attachments under security scope and compares bytes, while registration completion, foreground presentation, and action callbacks are recorded separately.

## Japanese source notes and historical evidence

0.8.0で公開したP1-B接続。0.7.0には含まれない。Foundation試験と通常hostのnative通知/添付/foreground UI試験に加え、2026-09-15の6beb877実機確認で通知カードの添付、記録、文字入力返信、owner別解除と通常前景方針を確認済み。集中モード下の配信は通常状態の成功へ含めない。

Appleの[UNNotificationAttachment](https://developer.apple.com/documentation/usernotifications/unnotificationattachment)は、検証した添付をOSの管理領域へ移す。Featureの文書や写真の原本をそのまま渡すと、通常画面が読むファイルを失い得る。`MiniAppNotificationAttachments`は任意の通常ファイルからowner別の一時コピーを作り、そのコピーで標準のnative requestを組み立てるための補助である。独自の添付型や通知機能を制限するwrapperではない。

```swift
let staging = try MiniAppNotificationAttachments(context: context, containerURL: appContainer)
try await coordinator.withStoreAccess(for: context.id) {
    try await staging.withFiles(copiedFrom: [photoURL]) { files in
        let content = UNMutableNotificationContent()
        content.title = "文書の更新"
        content.attachments = [try UNNotificationAttachment(identifier: "preview", url: files[0], options: nil)]
        // request ID/userInfo/categoryは既存のowner namespace/routeで設定する。
        let request = makeOwnedRequest(content: content)
        try await UNUserNotificationCenter.current().add(request)
    }
}
```

`operation`が完了する前に、native登録の完了もawaitする。ファイルを後で使うTaskを起動して先に成功を返してはならない。コピーはMainActorの外で行い、取消時も実際のコピー終了を待ってから解放する。native登録成功後に遅い取消を見て失敗へ変換しない。これは配信成功や原子的な通知の置換を保証するものではない。

コピー先は`Library/Caches/JibunKit/NotificationAttachments/<owner namespace>/<operation UUID>`。同じファイル名の複数添付や複数操作を共有しない。通常終了・エラー・取消時にはその操作のフォルダだけを片付ける。原本とOS管理領域は削除しない。終了時のcache削除失敗やprocess終了で残ったコピーは、ownerの処理をdrainした後に`removeStagingFiles()`で削除できる。他ownerのコピーは保持する。

すでにOSへ渡した添付の削除は、[Appleの仕様](https://developer.apple.com/documentation/usernotifications/unnotificationattachment)どおり対応するpending/delivered requestを`UNUserNotificationCenter`から削除する。Featureの管理削除はまず所有処理を止め、ownerの通知を解除し、その後に準備コピーや業務データを削除する。OS添付URLをキャッシュの掃除対象に混ぜない。取得済み添付の[URLへのアクセス](https://developer.apple.com/documentation/usernotifications/unnotificationattachment/url)にはsecurity scopeが必要。

Foundation試験では原本保持、nativeのmoveに相当する移動、登録失敗・取消・途中コピー失敗の掃除、A削除中のBコピー保持、取消要求後もoperation終了まではコピーを保つことをrun34802338245で確認した。通常Definitionと実UNUserNotificationCenterの登録/配信/取消、foregroundはrun34816553410のnetwork jobの2 UI methodでも成功。run全体は別Web jobの失敗によりfailureであり、通知の個別証拠として扱う。action/text inputの実機結果は下段に記録する。[P1-B記録](../verification/2026-09-14-p1-b.md)を参照。

## 0.8候補の通常接続（自動試験・OS操作を確認済み）

`Tests/TemplateIntegration/P1NotificationsProbe.swift`は通知A/Bを通常Definitionとして登録する診断画面。`prepare-p1-b-host.py`が指定された検証hostにだけ接続し、通常IPAへ常設しない。OSから読み返したpending添付をsecurity scope内で開き、画像原本とbyte一致を確認する。登録完了、配信時のforeground callback、通知操作callbackは別欄に表示する。Aはforeground非表示、Bはbanner/list/sound。同じローカルrequest/category/action名を両方で使う。

「準備後に停止して待つ」は準備コピーと通常store accessを保持し、明示取消または管理からの停止で終了する。時間経過では解放しない。管理から無効化すると受付を閉じて処理をdrainし、通知の解除と一時コピーの掃除を行う。無効化では画像原本を保持し、削除ではAの画像と操作記録も消す。登録前の故障注入では、既存のOS予約と原本を保持する。これはOS内部の全故障条件の再現ではない。

自動試験はnative予約/添付読込、取消、通常管理、B保持、foreground callbackを対象にする。6beb877の実機一括確認では、OS通知カードからの「記録」と文字入力「返信」、Bカードを残したA解除・管理削除、Aのsilent/Bのbanner方針を確認した。集中モード下で配信を確認できなかった範囲は成功扱いにしない。最終sourceの差分照合と出荷確認は[0.8出荷候補の照合](../verification/2026-09-15-0.8-release.md)に従う。
