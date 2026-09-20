# Receiving shared input and external files

## Current integration contract

The host accepts incoming URLs, documents, and share payloads, records them in a durable inbox, and routes them to the selected feature by explicit ownership rules. Copy security-scoped or temporary input into owned storage before the source lifetime ends. Never pass a transient provider URL directly into long-lived feature work.

Admission, cancellation, deduplication, and cold-launch retry belong to the incoming coordinator. A feature consumes only entries for its owner and generation, records completion durably, and leaves failed entries retryable. Build declarations and extension wiring do not by themselves prove provider or device behavior.

Attach an optional incoming adapter to `MiniAppDefinition`; keep business models and storage in the feature. Declare accepted UTTypes (including inheritance) and accept a destination only when it can handle every selected item—never silently import a subset. If several features qualify, ask the user; `incoming == nil` is never an implicit recipient. The user can inspect, choose, save, discard, or retry an item, and cancellation must leave a coherent durable state.

Stage content and its manifest under the owner namespace and receipt ID in the App Group Application Support directory. Publish the catalog entry only after every copy completes. Serialize the short catalog mutation separately from owner file I/O so A does not unnecessarily block B. Recheck the management/runtime generation before publication and reject an old copy after disable/re-enable. Save uses the same receipt for an idempotent retry when business persistence succeeded but acknowledgement failed.

The provider/host boundary owns security-scope access and temporary source lifetime; the feature receives stable staged files. Removal and discard delete only the owner's receipt directory after active work drains. Validate standalone, integrated, cross-process, UI, and real share-sheet/Files behavior as separate evidence.

## Japanese source notes and historical evidence

0.8.0で公開したP1接続。0.7.0には含まれない。native provider/所有試験は4e6a3f4で32件成功し、macOS別process試験も確認済み。本体UIで判明した受信/破棄ボタンの干渉を修正し、破棄確認を明示的な取消があるalertへ揃えた。修正後の本体UIはrun34794545131で、破棄取消・A保存後失敗・再起動・冪等再試行とB取込みが成功。4e6a3f4の実機で文字列/URL/ファイル共有、Files直接入力、取消、再試行後の重複なし/B保持、再起動・上書き/Refresh保持を確認済み。失敗直後の未取込み行は独立観測しておらず、CIの保持確認と区別する。Swift/iOS・OS共有シートの受入結果は[検証記録](../verification/2026-09-13-p1-a.md)で区別する。

## 通常Featureへの接続

Integrationの`MiniAppDefinition`にoptional `incoming`を付ける。Featureの業務モデル・保存方式をCoreへ移す必要はない。例えば文書Featureなら、受信した文字列やファイルを自分の文書storeへ保存する処理だけをadapterに置く。

```swift
MiniAppDefinition(
    id: id, title: "文書", systemImage: "doc",
    incoming: MiniAppIncomingProvider(id: id, typeIdentifiers: ["public.plain-text", "public.url"]) { receipt, directory in
        // 読み取った内容とreceipt.idを、同じ業務トランザクションで保存する。
        // ファイルはdirectory/item.valueから、receiveの終了前に読み取る。
        try await documents.importOnce(receipt: receipt, from: directory)
    },
    lifetime: lifetime,
    removal: ownedDocumentRemoval
) { context in DocumentRootView(store: documents) }
```

型の一致はUTTypeの継承を含む。複数項目の一部だけを黙って取り込まず、選択した受信先が全項目の型を扱える場合に保存する。受信先が複数なら利用者が選ぶ。`incoming == nil`のFeatureを自動的な受け手にはしない。

## 利用者の操作

OSの共有シートでJibunKitを選び、有効なミニアプリを受信先に指定すると、App Groupへ未取込みデータを保存する。その後、本体の「受信」で「取り込む / 再試行」を実行する。共有完了は受信保存の完了であり、Feature業務処理の成功ではない。

Files等からJibunKitで開いたファイルも、コピー後に受信先を選ぶ。バックアップや管理画面の操作中なら、その画面を閉じてから受信画面へ進む。新しい入力で既存の未保存入力を置き換えず、先の受信を完了・キャンセルしてから再度開くよう表示する。

失敗した受信は残り、再試行できる。不要な受信は確認後に破棄できる。無効化では未取込みデータを保持し、所有データの削除ではそのFeatureの未取込みデータも消す。別Featureの受信・保存済み文書には触れない。登録をビルドから除いたownerの未取込みデータも本体から明示的に破棄できる。

## 保存・取消・所有の境界

NSItemProviderの一時URLはcallback内でコピーし、security scopeを取得した場合は対応して解放する。callback到着前の取消は即座に待機を解く。既にコピーしているcallbackは終了を待ってから一時フォルダを消す。ファイルは通常ファイルを扱い、ディレクトリ・シンボリックリンクをファイルとして黙って解釈しない。独自のフォルダ形式等の追加受信方式は別途実装可能であり、iOS全体の必然的制約とはしない。

App Groupの`Library/Application Support/JibunKit/Incoming/owners/<namespace>/<receipt ID>`にコピーとmanifestを持つ。部分コピーは一覧に公開しない。catalogの短い同期とowner別のファイル同期を分け、Aのコピー・取込み中にBが待たされる範囲を限定する。無効化・再有効化の世代が変わった場合、古いコピーの公開を拒否する。

hostのDeliveryは通常のFeatureLifetime/RuntimeとStoreAccess予約に参加する。同じ受信の二重実行や別sceneからの実行中破棄はprocess内で拒否する。Coreが渡すファイルはawaitしたreceiveの間だけ有効なので、Taskを投げたまま成功を返してはならない。

FeatureのDB更新と受信ACKは異なる保存先で、一般に一つのatomic commitにできない。**receipt.idによる冪等保存は受け手の責務**。同じIDの再試行では同じ業務効果を二重に起こさず、本文とIDを同じトランザクションで保存する。receiveが成功した後の遅い取消を失敗へ変えず、受信をACKする。receiveが失敗した場合はACKしないが、Feature内で何も変更していないとはCoreから断定できない。

## ビルドと検証

通常hostはShare Extensionを埋め込み、host/Shareの同じApp Group、extension point、principal class、版番号、実行ファイル、署名をIPA生成時に検査する。外部ファイルを受けるDocumentTypesもhostへ宣言する。Extensionへ任意のFeatureの業務コードを埋め込まず、共有catalogにある受信先へ永続保存する。

検証用二Featureは`Tests/TemplateIntegration/P1IncomingProbe.swift`。普通のDefinition・独立した文書JSONを使い、保存後の応答失敗→同じreceiptの再試行、A/B保持、再起動保持とOS ShareLink操作を用意している。単体・iOS native provider・macOS別process・本体UIの証拠と、実機のOS共有操作は別々に記録する。実機結果のsourceと観測範囲は[実機記録](../verification/2026-09-14-0.8-device-check.md)、最終候補の再利用照合は[出荷記録](../verification/2026-09-15-0.8-release.md)を参照する。
