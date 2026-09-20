# Feature privacy manifests

## Current integration contract

Ship a feature's privacy manifest as a package resource owned by that feature. The host build must preserve and validate every included manifest, while removal of the feature product must also remove its manifest contribution. Do not merge declarations by hand in a way that hides their source or leaves stale entries behind.

Manifest presence and archive inspection are build evidence only. The adopting application remains responsible for accurate declarations that match its actual APIs, SDKs, data collection, and distribution configuration.

Place `PrivacyInfo.xcprivacy` in the feature or SDK target and register it as a Swift package resource. The host consumes the normal package product and keeps the feature-specific resource bundle; do not transcribe or concatenate declarations into a host-owned dictionary. Add the product to a widget target only when that target directly uses the SDK. Removing a feature from a shipping configuration means removing its package dependency and regenerating/rebuilding; in-app management removal affects registrations and owned data, not code or manifests in the IPA.

## Japanese source notes and historical evidence

Featureまたは依存SDK自身のtargetに`PrivacyInfo.xcprivacy`を置き、Swift packageでは明示resourceとして登録する。

```swift
.target(
    name: "ExampleFeature",
    resources: [.process("PrivacyInfo.xcprivacy")]
)
```

hostは通常のpackage product dependencyとしてFeatureを組み込む。manifestをhost用の独自辞書へ転記・連結せず、SwiftPM/Xcodeが作るFeature別resource bundleを配布bundleへ保持する。WidgetがそのSDKを直接利用する場合はWidget targetにもproduct dependencyを登録する。利用しないtargetへ申告を複製しない。

Featureをビルド構成から除去する場合は`Project.swift`のpackage dependencyを外し、`tuist generate`と通常のbuildを再実行する。同一project root・同一DerivedDataでも、Xcodeが該当resource bundleを除去し、残るFeature/SDKの`PrivacyInfo.xcprivacy`を保持することを検証済み。追加cleanや独自の清掃処理は不要だった。[clean/incremental比較の証拠](../verification/2026-09-11-privacy-manifest-ownership.md)を参照。アプリ内の管理削除は登録・所有データが対象であり、IPA内のコードやprivacy manifestを除去する操作ではない。

manifestは実際のデータ収集・tracking domain・required-reason APIと一致させる。bundleにファイルが存在してplistとして読めることは配置証拠であり、App Store Connectのprivacy detailsが正しいことやXcode Organizerの集約privacy reportを審査済みにするものではない。
