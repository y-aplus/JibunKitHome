# P2-I external identity 提出

> Historical note: this is the implementation submission at its original verification boundary. Current policy keeps generic HTTP mandatory and CloudKit optional with real communication unverified; use [the current contract](P2-identity-push-contract.md), [plan.json](plan.json), and [status](../status.md).

- 基点: `7347b483936e7f8bfe45d36984c32390cdcae2b3`
- 初回実装 commit: `a5bf420f52f29efda3a8b804f9bb58efd3e96e8a`
- lifecycle/管理/native修正 commit: `092fa5a9186c39e6fe3035df6050a545ef6e3844`
- account snapshot照合修正 commit: `779d77f0b28961117d4c75e12eb134625774f50e`
- branch: `codex/p2-identity`

## 変更契約

- container/account/data の完全な identity を `owner + container identifier/database + account identifier/generation + localID`
  とした。同じ local ID の二 owner は別 custom zone、別 record ID、別 subscription ID になる。
- backend 永続 key は `owner + container + account + localID` で、runtime generation を含めない。同じ account の停止・復元・
  再開後も同じ値を読む。generation は受付/遅着拒否だけに使う。
- coordinator は開始/account変更ごとの個別 reservation と runtime session を持つ。受付閉鎖後に所有 operation を取消・joinし、
  旧応答を `.staleGeneration` として隔離してから新世代を開始する。停止後の新 mutation は受け付けない。取消前に CloudKit
  server がcommit済みの書込みを巻き戻す保証はしない。
- `MiniAppExternalIdentityFeature` は既存 lifetime/removal に加えて `MiniAppExternalAccess` を接続する。管理 close が lifetime.stop
  より先に admission を閉じ、停止後も deletion 用 account snapshot を保持するため、実 `MiniAppManagement.remove` の順序で
  A zone を削除しBの runtime/値を維持できる。process再開でsnapshotがない場合は、停止状態のまま現在accountだけを照合する。
- native adapter は CloudKit 標準の `CKContainer`、private `CKDatabase`、custom `CKRecordZone.ID`、
  `CKRecord.ID`、`CKRecordZoneSubscription` を使う。任意 container 移行、shared/public database の共有設計、競合解決、
  汎用 sync engine は実装していない。
- String field adapter は既存 record をfetchしてchange tagと未指定fieldを保ったまま更新する。これはCloudKit全機能のfacade
  ではなく、任意CKRecordを使うFeature向けには `CloudKitExternalIdentityNames` のowned ID helperを公開する。record zone作成は
  `modifyRecordZones` のowner zone個別結果を成功確認してから次へ進む。
- native backendの `CKAccountChanged` observerはFeature runtime taskが所有し、停止時に解除する。停止中の通知は再activateしない。
- native全操作はidentity/snapshotのaccount identifierを現在の`CKContainer.userRecordID()`と照合する。await後とmutation直前にも
  account/取消を再検査し、停止中に別accountへ切り替わった場合はowner zone削除を拒否して管理のremoving intentを保持する。
  account照合と次のCloudKit requestは別OS requestであり、切替との完全な原子性は保証しない。
- native adapter は署名済み host が明示生成した `CKContainer` の注入を必須とする。Core、通常の Probe 定義、
  unavailable backend は `CKContainer()` を呼ばないため、entitlement なしの診断 host を定義生成だけで落とさない。
- fake backend の成功と実 CloudKit 通信成功を分離した。署名専用試験は通常 native targetから別sourceへ分け、通常試験には
  skipを置かない。

## ソースと試験

- Core: `Sources/JibunKitCore/ExternalIdentity/`
- unit: `Tests/JibunKitCoreTests/ExternalIdentity/MiniAppExternalIdentityCoordinatorTests.swift`
  - 二 owner の同名 record、片側削除/B保持
  - account 変更と旧 handle 拒否
  - account 変更/停止後の遅着隔離
  - activation 失敗からの復旧と B 保持
  - 閉じたruntimeへの接続rollback、runtime所有account observerと停止後非再起動
  - 実 `MiniAppManagement.remove` の停止→snapshot削除→再enableと B runtime・値保持
  - 管理停止後のaccount切替で誤account削除拒否、旧account値保持、元accountでの削除再試行
- native fixture: `Tests/P2Identity/P2IdentityProbe.swift` は二つの `MiniAppDefinition` と、署名 host 用 backend factory を公開。
- native tests: `Tests/P2Identity/P2IdentityNativeTests.swift` はskipなしで所有、削除、account変更、遅着、失敗/復旧、実Featureの
  管理remove、復元、終了接続を検証する。
- signed native: `Tests/P2IdentitySigned/P2IdentitySignedCloudKitTests.swift` は通常診断appへコピーしない署名専用source。
  明示containerでcreate/update（未指定field保持）/fetch/deleteを実通信する。
- guide: `docs/guides/external-data-identity.md`

## 検証結果と未実行

- `git diff --cached --check`: 成功（実装 commit 前）。
- 所有 path 照合: 変更は指定された Core/tests/guide/submission と、レビュー指定の `Tests/P2IdentitySigned/` 内。host、`Project.swift`、workflow、共通台帳、
  元の `C:/Dev/JibunKit`、ignored Zaiko は未変更。
- `swift test --filter MiniAppExternalIdentityCoordinatorTests`: **未実行**。この Windows host に `swift` executable がなく、
  PowerShell が command-not-found で終了した。試験失敗や成功として扱わない。
- Xcode/iOS build、native fixture、署名 CloudKit round-trip: **未実行**。親が source 統合後にまとめて実行する契約のため、
  CI dispatch は行っていない。
- Apple一次資料で `modifyRecordZones` の `saveResults` と `subscription(for:)` async API署名を照合した。実SDK compileの代替ではない。
- fake backend 試験ソースは実 OS 通信の証拠ではない。実 CloudKit 成功は署名専用 test の実行結果だけで判定する。

## 親 host への必要接続

1. 診断 target に `Tests/P2Identity/P2IdentityProbe.swift` と `P2IdentityNativeTests.swift` を追加し、既存方式で二 definition を
   registry へ合成する。entitlement なしの host は `P2IdentityProbe.definitions`（unavailable backend）を使う。
2. 署名 native host だけが `CKContainer(identifier:)` を生成し、`CloudKitExternalIdentityBackend(container:)` を作り、
   `P2IdentityProbe.features(backend:)` の返す Feature を保持して各 `.definition` を registry へ渡す。
3. 既存 `FeatureBuildRequirement` 合成へ app target の
   `com.apple.developer.icloud-container-identifiers = [<container>]` と
   `com.apple.developer.icloud-services = ["CloudKit"]` を追加する。profile/capability と一致しない ad-hoc 宣言を成功扱いしない。
4. account observerはnative backend/Feature lifetime内で接続済み。host独自のowner分岐は追加しない。管理registrationには
   definitionのlifetime/removal/**externalAccess**を渡し、restoreは`effectiveRestoreLifecycle`を使う。
5. `Tests/P2IdentitySigned/` は通常native targetへ入れず、CloudKit entitlement/profileを持つ専用targetだけへ追加する。
   private database custom zone と環境変数を必須にして実行し、設定欠落をskipで成功扱いしない。
