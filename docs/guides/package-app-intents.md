# Defining App Intents in a Swift package

## Current integration contract

Keep App Intents, App Entities, queries, and stable identifiers in the feature package, then link the package product into every target that must expose them. The host composes metadata and lifecycle wiring; it must not copy the declarations into application code.

Intent execution is a separate process/lifetime boundary. Resolve durable identifiers, open only the required feature operation, and use normal admission, storage, consent, and error handling. Compare standalone and integrated metadata and verify that removing the product removes its contribution.

Declare the standard `AppIntentsPackage` in both package and host and add the feature product to every app/extension target that exposes it, including `includedPackages`. This is independent of runtime `MiniAppDefinition` registration. In the verified route, the host's single `AppShortcutsProvider` references package intent types; use the feature shortcut-fragment guide when the feature owns the expressions.

Give every OS-visible intent, entity, and query a feature-owned stable `persistentIdentifier`; package separation alone did not prevent same-named entity/query metadata from collapsing. Keep entity and query identifiers distinct. Do not create an intent-only store. Inject a small async/throwing operation boundary into Core-independent packages and connect it to the same owner in `MiniAppRestoreCoordinator.withStoreAccess`. Hold the reservation until awaited persistence/cancellation finishes.

Initialize saved management state before injecting boundaries, including on cold launch, rather than from an enabled-only hook. Reads, writes, and entity queries reject disabled/removed owners. Commit a new value once, preserve the old value on throw/cancel, and never touch another owner. Removal callbacks already hold exclusive admission and therefore call reserved low-level deletion without reentering `withStoreAccess`.

Compare standalone and combined generated metadata for identifiers, types, parameters, results, modes, entities, and queries. Direct `perform()` tests cover business/storage behavior only. Test OS discovery, picker choices, saved workflows, cancellation UI, relaunch, management rejection, and Siri separately. Also scan the combined metadata for a definition that disappeared through collision; a successful build alone is insufficient.

## Japanese source notes and historical evidence

FeatureのIntent実装はapp targetへ移動せず、Swift Packageの公開型として置ける。標準`AppIntentsPackage`をpackage側とhost側で宣言して接続する。JibunKit独自のメタデータ生成やIntent wrapperは不要。

```swift
// FeatureのSwift Package内
import AppIntents
public struct NotesIntentPackage: AppIntentsPackage {}
public struct NotesAddIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add note"
    @Parameter(title: "Text") public var text: String
    public init() {}
    public func perform() async throws -> some IntentResult {
        // Feature自身のservice/storeへ接続する。
        return .result()
    }
}
```

これは接続形だけの例であり、保存処理は省略している。実際のIntentでも通常画面と同じFeature所有の保存・寿命・復元調停を使う。

```swift
// Sources/JibunKit等のapp target内
import AppIntents
import NotesFeature
struct JibunKitIntentPackages: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [NotesIntentPackage.self]
    }
}
```

`Project.swift`のapp targetにFeatureのpackage product dependencyも登録する。単独appや別extensionでも、各targetのpackage dependencyと`includedPackages`へ必要なものだけを登録する。RuntimeのMiniAppDefinition登録とは別のビルド時接続である。

自動提示するApp Shortcutは、現在検証済みの経路ではhostの一つの`AppShortcutsProvider`からpackageのIntentを参照する。任意のIntentすべてをApp Shortcutへ登録する必要はない。FeatureがShortcut式を所有する場合は[ソース合成ガイド](feature-app-shortcuts.md)を使う。Package Providerの参照を転送するだけではnative抽出を通らなかったため、式を一つの標準Providerへ配置する。

二Packageの単独/統合appで、Xcodeが生成した識別子・型名・引数・戻り値・実行modeの一致と、iOS上の`perform()`から他Featureを変更しないことを検証した。[native fixtureと証拠](../verification/2026-09-11-package-app-intents.md)を参照。この初回の証拠にはOS Shortcuts/Siriからの起動、AppEntity query、同名型衝突、Widget/Controlへの接続を含めない。後続のentity/query比較は下記を参照。

Intentの永続識別子は他Featureと区別できる値にする。同名Swift型もmoduleを分け、標準persistentIdentifierを明示する方法でnative比較済み（[証拠](../verification/2026-09-11-same-named-package-intents.md)）。既に利用中のIntentを移動・改名するときは、保存済みShortcutとの互換性を別途確認する。既存Counter intentは今回移動しておらず、元の識別子を維持している。

Apple標準の契約: [AppIntentsPackage](https://developer.apple.com/documentation/appintents/appintentspackage)、[App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)。

## 同名のAppEntity/queryと永続識別子

Swift Packageを分けるだけではnative metadataの名前衝突を防げなかった。同名`Entry`と`EntryQuery`が統合時に一件ずつへ減ることを確認した。[失敗と修正の証拠](../verification/2026-09-11-package-entity-queries.md)。新規FeatureではOSへ公開する型にFeature所有の安定した識別子を定め、標準`persistentIdentifier`を明示する。entityとqueryは別々に指定する。

```swift
public struct Entry: AppEntity {
    public static let persistentIdentifier = "com.example.notes.entry"
    // 通常のid、defaultQuery、表示・propertyを定義する。
}
public struct EntryQuery: EntityStringQuery {
    public static let persistentIdentifier = "com.example.notes.entry-query"
    // 通常のID解決・検索・候補を実装する。
}
```

この例は識別子宣言の抜粋。型名とレコードIDはFeature内の名前を使える。二Packageの同名型・同じレコードIDについて、native metadataの両方の保持、検索・候補、編集後の再取得、削除時の他owner非参照をCI 34558958859で確認した。OS Shortcutsの候補UI/保存済みworkflow実行は別の検証境界である。

既存公開型の永続識別子を不用意に変更しない。改名・移動・独立appからの統合時は以前の識別子との互換性を確認する。毎回のUUID生成やhost名からの自動再生成は使わない。独自メタデータ書換えやquery転送機構は不要。

Apple標準: [PersistentlyIdentifiable](https://developer.apple.com/documentation/appintents/persistentlyidentifiable)、[persistentIdentifier](https://developer.apple.com/documentation/appintents/persistentlyidentifiable/persistentidentifier)。

## 通常保存・管理へ接続する

Intent用に別の保存先を作らず、通常画面と同じFeature storeを呼ぶ。Core非依存のFeature packageでは、storeに小さなoperation boundaryを注入し、統合側で`MiniAppRestoreCoordinator.shared.withStoreAccess(for:)`へ接続する。非同期処理を受けるboundaryはasync/throwsで、awaitした保存・取消の終了まで予約を保持する。Taskを起動した直後に予約を解放しない。owner IDは通常の`MiniAppDefinition`、`MiniAppManagement.Registration`、backup/restoreと同じものを使う。管理の初期化が保存済みのdisabled/removed状態をcoordinatorへ反映するため、Intentの読み書きとentity候補取得は対象ownerが無効なら拒否される。

保存は新しい値を確定してから一度だけ置換し、throw/cancellationを成功結果へ変換しない。失敗後も以前の値を残し、別ownerの保存には触れない。管理削除のcallbackは既にownerの排他予約内なので、そこで`withStoreAccess`を再入せずstoreの予約済み削除操作を呼ぶ。画面の非表示は無効化ではない。

`Tests/PackageAppIntents`はP1-Aの検証fixtureとしてこの接続を二ownerで検証する。Combined系appは`App`初期化時、UI構築前に保存済み管理状態をcoordinatorへ反映してから境界を注入する。これは有効Featureだけに呼ばれる`onHostLaunch`へ置かない。既存のIntent/entity/query/parameter/result/phrase識別子比較に加え、直接`perform()`の引数と戻り値、候補検索、取消、保存失敗、再試行、管理再構築後の保持、A無効化・削除時の拒否とB保持を確認する。直接実行試験は保存ロジックの証拠であり、OS Shortcutsの発見や保存済みworkflowの証拠ではない。2026-09-14時点でCI 34746211458の7 unit＋1 managed host UI、通常host UIが成功し、生成hostと独立A/Bのnative定義8件も一致した（[証拠](../verification/2026-09-13-p1-a.md)）。公開0.7.0にはこのP1変更を含めていない。

## 0.8.0のOS確認

候補IPAを実機へ入れ、ShortcutsアプリからA/Bのactionを発見し、entity候補を選んだworkflowを保存する。正負の引数と返却値を確認する。取消はFeature画面の「次の保存を20秒遅延」で一度だけ遅延を設定し、保存workflowを開始して20秒以内にShortcutsから停止する。保存失敗は「次の保存を失敗」を設定して次のworkflowを実行し、失敗表示、旧値保持、その次の再試行成功を確認する。診断設定は既存Intentの引数や識別子を変更しない。さらにアプリ再起動後の値、通常管理からAを無効化した後の保存済みA workflow/query拒否とB workflow/B候補保持、A削除・再有効化後のA空状態とB保持を確認する。通常加算・候補・再起動・管理は6beb877、取消・保存失敗・次回成功は4e6a3f4の実機で確認済み（[結果とsource](../verification/2026-09-14-0.8-device-check.md)）。Siri音声呼出しは独立には確認していない。OS表示・候補・workflow保存・Siri/Shortcuts実行はSimulatorの直接`perform()`で代替せず、最終sourceの差分照合と出荷確認を別に行う。

## 統合で消えた定義を検出する

通常のbuild成功だけでは同名定義の衝突を検出できなかったため、意図した単独版のnative metadataと統合版を比較するツールを用意した。

```sh
python3 Tools/verify-app-intents-integration.py \
  --baseline /path/to/StandaloneA.app/Metadata.appintents/extract.actionsdata \
  --baseline /path/to/StandaloneB.app/Metadata.appintents/extract.actionsdata \
  --integrated /path/to/Combined.app/Metadata.appintents/extract.actionsdata
```

引数には統合後も残す予定の定義を持つ、Xcode生成JSONを指定する。検査はIntent/entity/queryのidentifier衝突、統合後の型の欠落・置換、entity引数・query・property参照の変化を拒否し、衝突した識別子と型名を示す。複数baselineが同じ型・参照を含む場合は重複登録として扱わず、統合版の追加定義も許容する。異なる単独appの無関係なhost専用Intentまでbaselineへ含める用途ではない。

これは明示したbaselineの保持検査であり、全依存関係の自動発見や、Shortcut文言・Siri実行・既存workflow互換性の包括検査ではない。出力metadataだけを渡して既に失われた定義を推測することもできない。既存Package比較CIはこの検査に加え、entity/query辞書全体の比較とiOS直接実行を続ける。
