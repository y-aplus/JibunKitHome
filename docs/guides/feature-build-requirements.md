# Composing feature build requirements

## Current integration contract

Each feature declares only the build inputs it actually needs. The host composes plist fragments, entitlements, privacy resources, background modes, URL schemes, and localized usage descriptions, and must fail on incompatible duplicate declarations instead of choosing one silently. Package resources and extension metadata remain owned by their defining feature.

Signing and provisioning are host responsibilities. CloudKit and APNs are optional capabilities and require host credentials plus real-service verification; fixture builds and metadata checks do not prove communication. Generic HTTP support remains mandatory and must not depend on either optional capability.

Register each target's declarations in `EnabledFeatureBuildRequirements.swift` and call `FeatureBuildConfiguration.compose`; keep app and widget configurations separate. Identical scalar values are shared. String-array keys such as background modes, task identifiers, query schemes, user activities, App Groups, Keychain groups, and Associated Domains are deduplicated and sorted. Any other differing value fails with its key and owners until the integrator supplies an explicit plist/entitlement resolution; do not concatenate usage text or use last-writer-wins.

For `CFBundleURLTypes`, preserve each dictionary and deduplicate only exact matches. A shared URL name with different dictionaries requires an explicit complete resolution; the same scheme under different names is allowed and runtime routing resolves ownership. Other structured arrays likewise require an explicit composed result. Reject empty/duplicate owners, wrong types for set-like keys, and resolutions for unrequested keys. Bundle ID and executable stay target settings.

Use the generated entitlements for Xcode and CI signing, but distinguish inclusion in a signed IPA, acceptance after third-party re-signing, and successful OS service use. Capability acquisition, provisioning, scheduler registration, permission prompting, and feature consent remain outside composition.

For localized usage text, declare `localizedInfoPlist[locale][key]`; identical values merge and conflicts require `localizedInfoPlistResolutions`. Write to a generated-only directory with `writeLocalizedInfoPlistStrings` and include it as target resources. Regeneration removes only generated `InfoPlist.strings`, not unrelated resources. App and widget use separate outputs, host values participate in the same rules, and diagnostic-only permissions must not leak into production. Bundle inspection proves packaging, not the language shown by an OS prompt.

## Japanese source notes and historical evidence

統合したFeatureのInfo.plist/entitlementsは、一つのnative targetの設定になる。各Featureの要求を`Tuist/ProjectDescriptionHelpers/EnabledFeatureBuildRequirements.swift`へ登録する。Tuist標準のProjectDescriptionHelpersとPlist.Valueを使い、追加の設定形式や製品用generatorを設けない。

```swift
import ProjectDescription

public enum EnabledFeatureBuildRequirements {
    public static let app = FeatureBuildConfiguration(features: [
        .init(owner: "camera", infoPlist: [
            "NSCameraUsageDescription": "写真を撮影します",
        ]),
        .init(owner: "scanner", infoPlist: [
            "NSCameraUsageDescription": "書類を読み取ります",
        ]),
    ], infoPlistResolutions: [
        "NSCameraUsageDescription": "カメラで写真を撮影し、スキャナーで書類を読み取ります",
    ])
    public static let widget = FeatureBuildConfiguration()
}
```

`app`と`widget`は別々に合成し、必要なtargetへだけ要求を登録する。FeatureのSwift package依存とRuntime Registryの登録も従来通り必要で、実行時のMiniAppDefinitionからビルド済みのplistを書き換えることはできない。別target/standalone appでも同じ`FeatureBuildConfiguration.compose`を使える。

## 合成規則

- hostと各Featureが同じkeyへ同じ値を指定した場合は共有する。独自key、ネストしたdictionary、数値等のTuistのplist値も指定できる。
- `UIBackgroundModes`、`BGTaskSchedulerPermittedIdentifiers`、`LSApplicationQueriesSchemes`、`NSUserActivityTypes`、App Group、Keychain access group、Associated Domainsは文字列配列を重複除去・ソートして合成する。
- それ以外の異なる値は、keyと要求元を示して生成を止める。用途説明を単純連結したり、最後のFeatureで上書きしたりしない。統合担当が`infoPlistResolutions`/`entitlementResolutions`へ合意した値を明記する。
- `CFBundleURLTypes`はhostとFeatureの辞書をそのまま集め、完全に同じ宣言だけを重複除去する。name/role/icon/独自metadataを落とさない。同じ`CFBundleURLName`に異なる辞書があれば、所有者を表示して明示resolutionを求める。nameなしの宣言も許可する。同じschemeを異なるnameで使うことは禁止せず、受信先は[実行時のURL resolver](feature-url-routing.md)で調停する。
- document types等、それ以外の構造化配列は異なる要求なら明示的に合成結果を指定する。一般的なkey別schema validatorはまだ提供しない。
- 空/重複のowner、文字列集合keyの不正な型、要求のないkeyへの余ったresolutionを拒否する。bundle identifier/executableはFeatureのplistで変更せずnative targetで設定する。

独自のnative target設定を禁止するものではない。たとえば外部SDKの特殊な設定は通常のTuist APIで表現できる。helperが扱わない設定の共存条件や、明示resolutionが各Featureの動作要件を満たすかは統合側で確認する。

## 署名・OS・実行時との境界

Tuistが生成したentitlementsをXcode設定とCIのad-hoc署名の両方で使用する。古い固定entitlementsファイルを別途署名へ渡す経路は削除した。指定値がIPAの署名へ入ることと、SideStore再署名後に許可されること、OSサービスを実際に利用できることは別々に検証する。

この合成はcapabilityを取得せず、プロビジョニングを購入/変更しない。background modeの宣言とは別にscheduler登録・期限・再配送を接続する必要があり、権限用途説明とは別に[Feature内の利用同意](feature-consent.md)を通常管理へ接続する。Feature別同意はP0-Bで実装・検証済みだが、OSの同意単位はホストアプリのままである。署名依存の必然的な条件と、残るJibunKit実装の仕事を混同しない。

[検証記録](../verification/2026-09-11-feature-build-requirements.md)と、Tuist公式の[コード共有](https://docs.tuist.dev/en/guides/features/projects/code-sharing)、[entitlements](https://tuist.github.io/tuist/main/documentation/projectdescription/entitlements/)を参照。

## 多言語InfoPlist.strings

用途説明はFeatureごとの`localizedInfoPlist[locale][key]`として登録する。同一locale/keyが同値なら保持し、異なる場合はhostが`localizedInfoPlistResolutions`へ最終文言を明記する。空locale/key、未要求locale/keyへのresolutionは拒否する。

```swift
let app = FeatureBuildConfiguration(features: [
    .init(owner: "camera", localizedInfoPlist: [
        "en": ["NSCameraUsageDescription": "Take photos"],
        "ja": ["NSCameraUsageDescription": "写真を撮影します"],
    ]),
    .init(owner: "scanner", localizedInfoPlist: [
        "en": ["NSCameraUsageDescription": "Scan documents"],
        "ja": ["NSCameraUsageDescription": "書類を撮影します"],
    ]),
], localizedInfoPlistResolutions: [
    "en": ["NSCameraUsageDescription": "Use the camera to scan documents"],
    "ja": ["NSCameraUsageDescription": "カメラで書類を撮影します"],
])
let build = try app.compose(infoPlist: hostPlist, entitlements: hostEntitlements)
try build.writeLocalizedInfoPlistStrings(to: "GeneratedResources/AppInfo")
```

生成先をtargetの`resources`へ渡すと、Apple標準の`<locale>.lproj/InfoPlist.strings`としてbundleへ入る。`Project.swift`はapp/widgetを`GeneratedFeatureResources/App`と`Widget`へ書き、通常製品targetへ自動接続している。Feature登録の追加・除去後は通常の`tuist generate`だけで反映される。

書出し先は生成専用ディレクトリにする。このAPIは再生成時に指定先の各`*.lproj/InfoPlist.strings`を除去してから書く（`Localizable.strings`等の別resourceは削除しない）。appとwidgetは別々のconfiguration・生成先を使い、片方の用途説明や表示名をもう片方へ流用しない。`compose(... localizedInfoPlist:)`へhost既存値を渡すと、hostもFeatureと同じ同値・衝突・明示resolution規則へ入る。これはFeature UI全体の翻訳frameworkではなく、Info.plistの人向け文字列だけを合成する。

診断hostも、採用したOS機能の用途説明を`infoPlist`のfallbackだけへ直書きせず、同じFeature要求の`localizedInfoPlist`へen/jaを登録する。複数Featureがマイク等の同一locale/keyへ同じ文言を要求する場合は同値として保持し、異なる目的を含む場合だけhostが`localizedInfoPlistResolutions`へ合意文言を明記する。OSが要求しない架空の用途説明keyは追加せず、通常appが利用しない診断権限を通常構成へ流入させない。

生成dictionaryとbuild済み`InfoPlist.strings`の読戻しは、同梱値とtarget分離の証拠である。実際のOS権限dialogが選択言語で表示されたことや、grant/deny後の挙動を証明するものではないため、採用した権限ごとのSimulatorまたは実機検証と区別して記録する。
