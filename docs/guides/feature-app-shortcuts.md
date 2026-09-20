# Feature-owned App Shortcut definitions

## Current integration contract

Define each feature's App Intents, entities, queries, phrases, and shortcut provider in the feature package. The host composes the package products and metadata but does not duplicate feature definitions. Keep persistent entity identifiers stable and route execution through the feature's normal admission and storage boundaries.

Verify both standalone and integrated metadata, including removal of a feature contribution. Metadata discovery is a build/runtime contract; invocation phrasing, system indexing, and device behavior require OS-level verification.

Keep each shortcut expression in the feature's `AppShortcuts.swift.fragment`, with no imports or provider declaration. From `Project.swift`, call `FeatureAppShortcuts.writeProvider` with a unique nonempty owner, required imports, and the fragment path, then add the generated Swift file to the app target. The normal package dependency and `AppIntentsPackage` registration are still required. An app has exactly one generated or handwritten provider; migrate handwritten shortcuts into fragments when combining them. Exclude a fragment stored inside a package target from compilation.

Generation places the unchanged Swift expressions in one standard provider, preserves diagnostics with `#sourceLocation`, reads all inputs before replacing output, and rejects duplicate owners, empty owners/files, and unreadable inputs. Removing an entry and regenerating removes its expressions; an empty list emits no provider. Do not edit generated output or treat this helper as a Swift parser/DSL—the compiler and metadata extractor validate phrases, parameters, and availability.

Keep fragment ownership aligned with the intent's definition, management owner, and store-access owner. Removing a build contribution differs from disabling/removing at runtime: a previously saved OS shortcut may remain, so `perform()` must reject through normal management and store admission. Removing A must not change B's expressions, entities, or stored values. Metadata comparison proves extraction and stable definitions, not gallery discovery, picker behavior, saved workflow execution, cancellation UI, or Siri voice invocation.

## Japanese source notes and historical evidence

状態: 単独/統合のnative metadata比較と寄与削除をCI 34550748042で検証済み。通常Counterの定義元をFeature側へ移す接続は[互換性検証](../verification/2026-09-11-host-shortcut-composition.md)をCI 34553604092で完了した。

App Intent本体はSwift Package内に置き、標準の[AppIntentsPackage接続](package-app-intents.md)で利用する。一方、今回のXcodeではPackage Providerだけの組込みでappのShortcut metadataが空になり、配列転送やcomputed property参照も抽出に拒否された。[比較証拠](../verification/2026-09-11-package-shortcut-providers.md)。この差分には、Feature所有のSwift式を生成時に一つの標準Providerへ配置する方法を用意する。

Feature内の`AppShortcuts.swift.fragment`に、通常の`AppShortcutsBuilder`へ書くSwiftの式を置く。

```swift
AppShortcut(intent: MyFeature.AddItemIntent(),
            phrases: ["Add an item in \(.applicationName)"],
            shortTitle: "Add item", systemImageName: "plus")
```

TuistのProject.swiftから、対象appに含める定義だけを列挙する。

```swift
import ProjectDescriptionHelpers

try FeatureAppShortcuts.writeProvider([
    FeatureAppShortcuts(owner: "my-feature", imports: ["MyFeature"],
        sourceFile: "Features/MyFeature/AppShortcuts.swift.fragment"),
], to: "Generated/MyAppShortcuts.swift")
```

生成ファイルをapp targetのsourcesへ追加する。通常のPackage依存とAppIntentsPackageの登録も必要。一つのappにはこの生成Providerか手書きProviderのどちらかを置く。既存の手書きShortcutを併用したい場合はその定義もfragmentへ移し、一つの生成Providerへ含める。生成物を手で編集せず、単独appと統合hostで同じFeature側のファイルを参照する。

通常hostの例はProject.swiftと`Sources/CounterIntegration/AppShortcuts.swift.fragment`。Counterの既存Intent型は公開済みの識別子を保つためapp moduleに残すが、Shortcutの文言と組立てはFeature側のfragmentが所有する。Package target内にfragmentを置く場合は、そのtargetの`exclude`へ追加する。

これはSwiftを解析する独自DSLではない。phrase、引数、availability等の式は変更せずに配置し、妥当性やOS条件はSwiftコンパイラとAppleのmetadata抽出で検証する。モジュール名を含む型名で他Featureと区別できる。`#sourceLocation`で定義元の行を診断へ残す。fragment内にimportやProvider宣言を重ねず、必要なimportは引数に指定する。

同じownerの二重登録・空のowner・空ファイル・読めないファイルは生成前に拒否する。全入力を読み終わってから一つの出力を置換するため、読み取り失敗時に以前の生成物を部分的に上書きしない。登録を外して再生成すればそのShortcut式も消え、空の登録ならProvider宣言を出さない。出力先は専用の生成ファイルを指定する。

OSのShortcut表示・Siri実行・app全体の枠や並び順などは、このソース組込みだけで解決したとは扱わない。metadata比較と実行検証を分ける。補助処理は本体のIntent識別子や実装、保存先、Runtimeを変更しない。

通常接続ではfragmentのownerと、Intentが使う`MiniAppDefinition`/management/store accessのownerを一致させる。登録を外す操作はShortcut式の寄与だけを消す場合と、通常管理でFeatureを無効化・削除する場合を区別する。後者では保存済みShortcut自体がOSに残り得るため、`perform()`入口の通常store accessが必ず拒否を返す必要がある。Aの寄与やデータを外してもBの式、候補、保存値を変更しない。

native metadataの単独A/B対統合比較と寄与削除buildは、成功後に永続識別子・phrase式・引数・戻り値が保持された証拠になる。`perform()` XCTestは成功後に保存と管理境界の証拠になる。P1-AではCI 34746211458によりnative比較と直接実行/管理の試験が成功し、生成hostのautoShortcutsにA/B/既存Counterの3寄与を確認した（[証拠](../verification/2026-09-13-p1-a.md)）。この変更は公開0.7.0には含まれない。また、どちらもShortcutsアプリでの発見、候補picker、workflow保存、保存済みworkflow実行、取消表示の代替ではない。通常の発見/候補/保存/実行/管理は6beb877、取消・失敗・次回成功は4e6a3f4で実機確認済み。[source別の実機記録](../verification/2026-09-14-0.8-device-check.md)を参照する。Siri音声呼出しの独立検証は含めない。
