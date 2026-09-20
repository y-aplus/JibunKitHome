# Integrating same-named pure Swift SDK modules

## Current integration contract

Use Swift package module aliases to resolve source-module name collisions while keeping product and target ownership explicit. Apply aliases consistently to every dependency edge that imports the renamed module, and verify both standalone and integrated builds.

A module alias does not resolve duplicate product names, Objective-C runtime names, resource bundle identifiers, generated metadata, or linker symbols. Those conflicts require distinct products/targets or upstream naming changes; do not present aliasing as a universal namespace mechanism.

On each consumer product edge, map the dependency's original module name to a unique alias with `moduleAliases`. Vendor SDK and feature sources keep `import VendorSDK`; SwiftPM propagates the alias through the dependency path. The packages must have distinct identities. This does not permit resolving two versions of one package identity or isolate OS singletons and external data.

The pure-Swift macOS fixture succeeds with aliased targets and fails without them. In the tested iOS/Tuist graph, target aliasing alone still hit an Xcode PIF collision because both packages published a product named `VendorSDK`. The working iOS fixture also renamed the public products to `VendorAProduct` and `VendorBProduct`, updated each feature's product dependency, and retained the target/module name plus aliases. That requires control or a maintained fork of the vendor manifests; do not claim arbitrary binary, C, Objective-C, or immutable third-party SDKs are supported.

## Japanese source notes and historical evidence

別々のPackageが同じmodule名をexportしている場合、SwiftPM標準の`moduleAliases`で
消費側の名前を分けられる。JibunKit独自の型名書換えやruntimeを追加する必要はない。

検証fixtureでは、FeatureA→VendorAとFeatureB→VendorBの二経路があり、VendorA/Bの
Package identityは異なるが、どちらも`VendorSDK`というmoduleを持つ。
両Featureを消費するPackageのtargetで、product edgeごとに次のように指定する。

```swift
dependencies: [
    .product(
        name: "FeatureA",
        package: "FeatureA",
        moduleAliases: ["VendorSDK": "VendorASDK"]
    ),
    .product(
        name: "FeatureB",
        package: "FeatureB",
        moduleAliases: ["VendorSDK": "VendorBSDK"]
    ),
]
```

SDKとFeatureのsourceは元の型名と`import VendorSDK`を維持する。SwiftPMが依存経路へ
aliasを伝播し、二つのmoduleを別名でコンパイルする。

[34684588973の比較](../verification/2026-09-12-package-sdk-aliases.md)では、aliasなしの
統合だけが`VendorSDK`と両Packageを明示する重複target診断で失敗した。aliasありでは
両SDKの版・初期設定・Bの書込値・A更新後のB保持が成功している。

これはmacOS上のSwiftPMで、別Package identityに置いたsource-builtな純Swift moduleを
検証した結果である。同一Package identityの複数version解決を可能にする証拠ではない。
C/Objective-C symbol、binary SDK、SDKが操作するOS singletonや外部データの所有権も
別途扱う必要がある。

iOSのTuist生成ホストでは[34685650822](https://github.com/y-aplus/JibunKit/actions/runs/34685650822)
で生成・解決が成功した後、Xcode 26.6が同名product `VendorSDK`のPIF参照重複で失敗した。
UI実行前の失敗であり、この構成をiOSで利用可能とは扱わない。module名のaliasと
Packageの公開product名は別の境界である。iOS向けに公開product名だけを分ける
manifest編集は[34686272759](https://github.com/y-aplus/JibunKit/actions/runs/34686272759)
で成功した。VendorA/Bの公開productを`VendorAProduct`/`VendorBProduct`へ分け、
各Featureのproduct依存名を合わせる。target/moduleは`VendorSDK`のままで、上記の
moduleAliasesを消費側bridgeに指定する。SDK/FeatureのSwift sourceは変更しない。

この構成では両SDKの版・設定がiOS画面へ表示され、Bを書き換えた後にAを更新しても
Bの値が保たれた。公開productの改名には依存Packageのmanifestを編集できること
（またはforkの保守）が必要で、任意の外部SDKに自動適用できる機構ではない。
元の同名product構成の失敗と、この改名した構成の成功を区別する。

設計上の基準はSwiftの[SE-0339](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0339-module-aliasing-for-disambiguation.md)に従う。
aliasだけで解決していない衝突を、解決済みとして扱わない。
