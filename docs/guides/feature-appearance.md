# Feature appearance and screen-awake requests

## Current integration contract

Express feature appearance as scoped SwiftUI environment or UIKit presentation configuration. Do not mutate process-global appearance as an incidental consequence of showing a feature. Restore host presentation state when the feature disappears.

Screen-awake behavior is a separate lease owned by the selected active scene. Aggregate requests centrally, apply the effective value to the host, and release it on deselection, scene deactivation, runtime stop, and failure.

Use `environment(\.colorScheme, ...)` only for a SwiftUI subtree. `preferredColorScheme` propagates upward to its hosting presentation and can affect sheets, so conflicting preferences inside one presentation are not an isolation boundary. For UIKit, set `overrideUserInterfaceStyle` on a feature-owned container or root controller; do not change `UIAppearance`, the application window, or a process-global third-party theme setter. A global SDK requires a feature-specific adapter plus explicit simultaneous A/B and restoration tests.

The fixture separately observes SwiftUI environment values, real hosting-controller and sibling-window traits, UIKit controller overrides, navigation and sheet behavior, and removal of a prior preference. Its `requested` value is feature intent; `effective` means the selected active scene owns the lease. Generated hosts copy `P2AppearanceProbe.swift` into app sources and register its definitions, while `P2AppearanceNativeTests.swift` belongs only in the native test target. Do not compile the probe twice or ship it in the product registry.

## Japanese source notes and historical evidence

Featureの外観は、独立アプリで使えたアプリ全体の設定をそのままhost全体へ適用しない。通常の接続ではSwiftUI環境、presentation preference、UIKit controller traitを区別する。

`environment(\.colorScheme, ...)`はそのSwiftUI subtreeが読む環境値を変更する。UIKitのtraitや別presentationまで変更した証拠にはしない。`preferredColorScheme`は単なるview-local環境値ではなく、presentationをホストするcontrollerへ上向きに働き、sheetを含むpresentation全体へ伝播し得る。同じpresentation内でAとBに相反するpreferred値を置く構成は隔離契約にしない。Featureごとに別のpresentation/controller境界がある場合だけ、その境界と別windowが保持されることを実traitで確認する。

UIKitではFeatureが所有するcontainer/root controllerの`overrideUserInterfaceStyle`を使う。これはそのcontroller subtreeへ適用され、兄弟controllerやwindowのstyleを変更しない。`UIAppearance`の無条件なglobal proxy、`UIApplication`やhost windowへの直接style設定、第三者SDKのprocess-global theme setterはこの通常契約の対象外である。必要ならFeature固有containerに限定したappearance APIまたはSDK adapterを設計し、A/B同時利用と終了後の復元を別途検証する。

`Tests/P2Appearance`のfixtureは次を分けて観測する。

- SwiftUI environmentが読む`colorScheme`
- `preferredColorScheme`を持つ実`UIHostingController`のtraitと別windowのtrait
- Feature所有UIKit controllerのoverrideと兄弟/windowのtrait
- 通常`NavigationStack` rootおよびsheet内の環境値・UIKit trait
- 同じhost presentation内でenvironment指定A→preferred指定B→sheet終了→A再訪した際のpreference除去

probeのA/Bは通常の`MiniAppDefinition`、`MiniAppFeatureLifetime`、`onSceneActivityChange`を使う。画面点灯要求は既存`MiniAppSceneIdleTimer`へ接続し、UIに`requested`（Featureの意図）と`effective`（現在leaseを持つowner）を別表示する。Aが要求中でもB選択時はAのeffectiveを解除し、Bの要求を有効化する。backgroundではeffectiveを解除し、activeで選択された場合に要求を復元する。

このfixtureが確認するのは`UIApplication.isIdleTimerDisabled`へ至る要求合成とtraitの読戻しである。c66b624診断版では、実機の要求中点灯維持と非選択後の通常自動ロックを確認済み。この実機証拠と自動trait試験を分けて扱う。任意sheetのさらに外側、別sceneのhost構成、global appearance setterを自動隔離したとは扱わない。

生成hostへ接続するときは、`P2AppearanceProbe.swift`をapp sourceへコピーして`P2AppearanceProbe.definitions`をregistryへ加える。`P2AppearanceNativeTests.swift`だけを専用native test targetへ入れ、`@testable import JibunKit_App`がコピー済みprobeを検査できるよう`JibunKit-App`と`JibunKitCore`へ依存させる。probe原本をtest targetにも重複コンパイルしない。製品`Project.swift`や通常registryへfixtureを常設しない。
