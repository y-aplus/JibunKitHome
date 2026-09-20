# External data identity and CloudKit integration

## Current integration contract

Keep external account identity separate from the local feature owner and runtime identity. A feature must remain usable through the mandatory generic HTTP integration even when CloudKit is not configured. CloudKit is an optional, host-signed capability: its container identifiers, entitlements, provisioning, and real-device communication must be supplied and verified by the adopting host. The repository fixtures validate composition and diagnostics only; they do not claim verified CloudKit communication.

Persist enough source and account identity to reject stale callbacks and cross-account data, but do not infer ownership from an external identifier alone. Route all external reads and writes through the feature-owned coordinator so shutdown, removal, and account changes can close admission before state is mutated.

Model identity as feature owner + backend/account identity + local ID + operation generation. Check the account before each request and again before publishing its result. Cancellation stops new mutation and local publication but cannot promise rollback of a write already accepted by a remote service. Account state can change immediately after a check, so surface that race and make operations/retries idempotent.

The generic backend protocol is the required integration and is exercised without service entitlements. A CloudKit adapter is an optional example: use an owner-specific custom zone and subscription IDs from `CloudKitExternalIdentityNames`, inject a host-created `CKContainer`, and keep feature schema/record/asset/reference operations in the feature. Build requirements add the iCloud container identifier and `CloudKit` service only to the adopting app. Merely enumerating the feature must not construct `CKContainer()` or crash an unsigned host.

Real CloudKit round trips live only in the signed test target and require `JIBUNKIT_CLOUDKIT_CONTAINER`; not running them is neither success nor a skipped generic native test. Verify save/fetch/delete separately through the injected container. Management, restore, and shutdown tests use a fake backend without skipping. Deleting one owner with a reused local ID must not affect the other.

## Japanese source notes and historical evidence

## 所有契約

`MiniAppExternalRecordIdentity` は次の全要素を持つ。Feature は `localID` だけを外部保存のキーにしない。

- `MiniAppID`（owner）
- CloudKit container identifier と database scope
- backend が返した account identifier と、その照合ごとに発行する generation
- Feature 内の `localID`

generation は runtime 内の受付・遅着判定だけに使う。backend の永続キーは
`MiniAppExternalPersistentRecordKey`（owner/container/account/localID）であり generation を含まない。同じ account で
停止・復元・再開しても既存データを読める。

CloudKit adapter は owner ごとに `jibunkit.<owner>` の custom record zone と subscription ID を使う。同じ
`localID` を A/B が使っても zone が異なる。管理から A を削除すると A の zone だけを削除し、B の record、
runtime、非初期値は変更しない。任意 container 間の移行、競合解決、業務データの汎用同期はこの API の範囲外。

## 通常 Feature への接続

署名済み host が container を明示的に生成して adapter へ渡す。

```swift
let container = CKContainer(identifier: "iCloud.com.example.Product")
let backend = CloudKitExternalIdentityBackend(container: container)
let external = MiniAppExternalIdentityFeature(
    id: featureID,
    container: try MiniAppExternalContainer(identifier: "iCloud.com.example.Product"),
    backend: backend
)

MiniAppDefinition(
    id: featureID,
    title: "Example",
    systemImage: "externaldrive",
    lifetime: external.lifetime,
    removal: external.removal,
    externalAccess: external.externalAccess
) { context in
    ExampleView(coordinator: external.coordinator)
}
```

`lifetime.start()` は cleanup を先に runtime へ登録してから account を照合し、subscription と account observer を用意する。
管理の `externalAccess.close` は lifetime 停止より先に受付を閉じる。coordinator は所有 operation を取消して完了まで join し、
その後に deletion 用 account snapshot を保持したまま runtime generation を無効化する。したがって管理が stop 後に呼ぶ
`MiniAppRemovalProvider` は snapshot の owner zone を削除できる。復元後は新しい runtime で再接続し、停止前の handle は
再利用せず `identity(localID:)` を取り直す。

native backend は `CKAccountChanged` observer を Feature runtime の task として所有する。停止時に observer を取消し、停止中の
通知は Feature を再activateしない。変更中は受付を閉じ、旧 operation を取消/joinしてから新 account を照合する。並行する
activate/account change は個別 reservation で後着だけを採用する。旧 handle の read/write/delete は `.staleGeneration` になる。

取消は新しい mutation とローカル結果公開を止める境界である。CloudKit server が取消前に受理済みの書込みを巻き戻す保証は
ないため、generation 照合を server transaction/rollback と呼ばない。

native adapter は各 load/save/delete/subscription/owner削除で、identity/snapshot の account identifier と現在の
`CKContainer.userRecordID()` を照合する。account切替を検出した場合は `.staleGeneration` とし、特に停止中の削除snapshotを
別accountの同名owner zoneへ適用しない。network await後とmutation呼出し直前にもaccountと取消を再検査する。ただし
CloudKitには「account照合と次の別request」を一つのOS原子的操作にするAPIはないため、最後の照合直後にOS accountが切り替わる
競合を完全には排除できない。削除失敗は管理のremoving intentとsnapshotを保持し、元accountへ戻して明示再試行する。

失敗した activation は runtime 起動失敗として扱われ、既存 `MiniAppFeatureLifetime` の停止完了後に再試行できる。
片方の account/通信失敗を別 owner の停止や削除へ拡大しない。

## CloudKit の前提と診断

実通信には次がすべて必要。

1. Apple Developer portal と署名 profile で iCloud/CloudKit capability が有効。
2. entitlements の container identifier が `MiniAppExternalContainer.identifier` と一致。
3. CloudKit Dashboard に schema/container があり、端末が iCloud account を利用可能。
4. custom zone を利用できる private database（製品で shared database を使う場合は共有契約も別途設計）。

親 host の既存 `FeatureBuildRequirement` 合成には、少なくとも app target の
`com.apple.developer.icloud-container-identifiers = [<container>]` と
`com.apple.developer.icloud-services = ["CloudKit"]` を Feature owner の要求として加える。複数 Feature の同じ
container/services は既存の文字列配列規則で重複除去する。profile にない entitlement を ad-hoc に足しても利用可能には
ならない。診断 host、通常 host、extension は別 target なので、不要な target へ宣言を流用しない。

Core、`P2IdentityProbe`、`UnavailableExternalIdentityBackend` は `CKContainer()` を呼ばない。したがって entitlement のない
診断 host も定義を列挙しただけでは落ちない。native adapter は、上記を満たす host が作成した `CKContainer` の注入を
必須にしている。

`CloudKitExternalIdentityBackend` は String field を使う小さな接続例であり、任意 CKRecord/asset/reference の facade ではない。
更新時は既存 record を fetch して change tag と未指定 field を保持する。より豊かな Feature は
`CloudKitExternalIdentityNames` の owned zone/record/subscription ID を使い、固有 schema/operation を Feature 内に実装する。

通常の `Tests/P2Identity/P2IdentityNativeTests.swift` は skip なしで fake backend と実 Feature の管理・復元・終了接続を検証する。
実 CloudKit round-trip は診断 app にコピーされない `Tests/P2IdentitySigned/P2IdentitySignedCloudKitTests.swift` だけに置き、
署名専用 target と `JIBUNKIT_CLOUDKIT_CONTAINER` を必須にする。未実行は成功でも通常 native test の skip でもない。

## 観測すべき結果

- 二 owner が `same-local-id` を保存し、片側削除後も他方を読める。
- account 変更前に開始した遅い応答が `.staleGeneration` になり、新 account の値を上書きしない。
- Feature 停止後の遅着が破棄され、再開時に新 identity を取得する。
- 一時的な account/通信失敗後の再起動で復旧し、他 owner の runtime/data は維持される。
- native round-trip だけは `CKContainer` を介した save/fetch/delete として別に記録する。
