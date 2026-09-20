# Opening feature screens from URLs

## Current integration contract

Keep URL resolution pure: parse and validate a URL into an explicit feature route before changing selection, scene state, or storage. Reject ambiguous, malformed, unsupported, or cross-owner routes instead of guessing. Execution then passes through normal runtime admission and presentation ownership.

The host composes URL schemes and universal-link metadata and must detect conflicts. Build-time declarations do not prove association-file deployment, system routing, cold launch, or multi-scene behavior; verify those in the adopting application.

Implement `MiniAppDefinition.resolveIncomingURL` as a side-effect-free parser that receives the original Foundation `URL` and returns `.root`, `.detail(String)`, or `nil`. The host asks every feature and routes only a single match into the navigation path of the scene that received the URL. The feature validates identifier syntax and existence in `appendDestination`. A rejected or ambiguous URL leaves the current screen unchanged; never prefer registration order. Reserved `jibunkit://` URLs use only the host's strict resolver and are not reinterpreted by features.

Custom schemes belong in the app target's `CFBundleURLTypes`; universal links require Associated Domains and the matching website association. Compose those through the feature build requirements, preserve the host declaration when resolving a conflict, and do not copy app-only schemes into widgets. This resolver handles address delivery only: web-auth completion, security-scoped files, generic action callbacks, `UIOpenURLContext` options, and OS multi-window selection use their dedicated boundaries.

## Japanese source notes and historical evidence

独立アプリのURL entry pointを単一hostへ統合すると、受信先Featureの選択が必要になる。`MiniAppDefinition.resolveIncomingURL`は元のFoundation `URL`を受け取り、受理する場合だけ`.root`または`.detail(String)`を返す。hostは全Featureの一致を調べ、一つだけならSwiftUIが配送したsceneの既存navigationへ接続する。

```swift
MiniAppDefinition(
    id: MiniAppID("notes"), title: "Notes", systemImage: "note.text",
    appendDestination: { identifier, path in
        guard let note = store.note(id: identifier) else { return false }
        path.append(NoteDestination(id: note.id))
        return true
    },
    resolveIncomingURL: { url in
        guard url.scheme == "mynotes", url.host == "note",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil else { return nil }
        let identifier = String(url.path.dropFirst())
        return identifier.isEmpty ? .root : .detail(identifier)
    }
) { context in NotesRootView(context: context) }
```

例のstore/NoteDestination/NotesRootViewはFeature自身の型。識別子の形式と存在確認はFeatureが行う。resolverは解析・検証だけを行い、保存変更、認証完了、削除、画面遷移等の副作用を起こさない。複数候補を調べるため、受理しないFeatureにもURLは渡る。これは協調するFeature間の配送契約であり、同一process内の機密境界ではない。

同じscheme/domainを複数Featureが共有し、pathなどで区別してよい。複数Featureが同じURLを受理すると`ambiguousOwners`で拒否し、登録順で優先しない。未知URL、曖昧URL、Featureが受理できないdetailは現在の画面を維持する。他Featureの経路は上書きしない。host予約の`jibunkit://`は既存の厳密な解決だけを使い、不正な予約URLをFeatureに再解釈させない。

OSがURLをhostへ配送する設定は別に必要。custom schemeはapp targetの`CFBundleURLTypes`、Universal LinkはAssociated Domainsと対応するwebサイトの関連付けを設定する。[Feature build requirements](feature-build-requirements.md)でhostとFeatureの要求を合成する。異なるnameのURL宣言は自動で集め、既存の`jibunkit` schemeも保持する。同じnameの異値衝突を明示resolutionで解決する場合は、hostを含む必要な宣言を解決値に保持する。実例は隔離CI用の`Tests/TemplateIntegration/URLRoutingBuildRequirements.swift.fixture`にある。Widgetへ不要なschemeを複製しない。

この接続は画面へのアドレス配送を扱う。ASWebAuthenticationSessionの完了処理は[Web認証](web-authentication-ownership.md)、外部ファイルのsecurity scopeと受信先選択は[共有入力](feature-incoming.md)の別経路へ接続する。P1の自動検証とsource別の実機結果を各ガイドで区別する。一般の操作callback、`UIOpenURLContext`のoptions、実OS上の複数window選択までこのresolverが自動で扱うものではない。

根拠: Apple [onOpenURL(perform:)](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))はcustom URL/Universal Linkとsceneへの配送を説明している。現在の検証範囲は[記録](../verification/2026-09-11-feature-url-routing.md)を参照。
