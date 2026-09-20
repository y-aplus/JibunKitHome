# Adding a feature

A JibunKit feature is source code compiled into the host at build time. The preferred shape is a Swift package with business logic and a root view, plus a thin integration that creates one `MiniAppDefinition`.

JibunKit does not load arbitrary IPAs or runtime plug-ins. It also does not automatically convert an existing app target: separate reusable feature code from the app shell first.

Prefer a separate package under `Modules/<Name>` for a new personal feature. It gives the feature an isolated test command, a standalone example, and a clearer reuse boundary; a portable package can also run its own tests on Linux/WSL even though the repository's root package cannot. Adding sources to the root package can be reasonable for code inseparable from the host, but it couples validation to the macOS/Xcode path and increases shared CI work.

## 1. Create a standalone feature

On macOS with Tuist 4.207.0:

```bash
tuist scaffold feature --name Notes
tuist generate --path Modules/Notes --no-open
```

Use a valid Swift type name beginning with an uppercase letter. The template creates a Swift package, root view, tests, a small example app, and UI-test scaffolding under `Modules/Notes`. It refuses to overwrite an existing directory.

The repository's scaffold and project-generation commands are macOS paths. In the reported Tuist 4.207.0 Linux experiment, the installed binary did not provide the local `scaffold` and Xcode-project `generate` commands used here; this is not a claim about every Tuist version. On Windows/WSL, create the package files manually or prepare them on macOS, then use the package-specific checks described in [Build, sign, and install](build.md).

Develop and test `NotesExample` independently. Keep domain models, persistence rules, validation, and feature-specific native behavior in this package. The feature package does not need to depend on JibunKitCore unless it directly uses its APIs.

## 2. Add the package to the host

In the root `Project.swift`:

1. Add `.package(path: "Modules/Notes")` to `packages`.
2. Add `.package(product: "NotesFeature")` to the `JibunKit-App` target dependencies.
3. Add the dependency separately to a widget or other extension only when that target imports the product.

The package must expose a library product. Do not add the generated example app's `@main` target to the host.

## 3. Define one integration

For this example, create `Sources/JibunKit/NotesMiniApp.swift`, which is already in the host source set. If you keep integration beside the package instead, explicitly include that integration source in the host target:

```swift
import JibunKitCore
import NotesFeature

@MainActor
enum NotesMiniApp {
    static let definition = MiniAppDefinition(
        id: MiniAppID("notes"),
        title: "Notes",
        systemImage: "note.text"
    ) { _ in
        NotesRootView()
    }
}
```

Add `NotesMiniApp.definition` once to `Sources/JibunKit/MiniAppRegistry.swift`.

The ID must begin with a lowercase ASCII letter and contain only lowercase letters, digits, `.`, `-`, and `_`. It becomes part of storage, notification, routing, backup, and system-registration identities. Treat a shipped ID as persistent data: do not rename it without a migration.

Keep the title, symbol, destination factory, lifecycle hooks, permissions, backup provider, and optional system integrations together in the definition or its integration layer. Do not add feature-specific switches to the host's list or navigation code.

## 4. Use owner-scoped APIs

`MiniAppContext` supplies identities and storage locations owned by the feature. Use it instead of global names for:

- UserDefaults keys and shared-state keys;
- files and database locations;
- notification requests, categories, and routing payloads;
- URL routes and detail destinations;
- backup, restore, removal, and external-input registrations.

These APIs coordinate cooperating features; they do not sandbox arbitrary Swift code. The feature remains responsible for data validation, schema migration, transactions, and correct native API use.

Add only the contracts your feature needs:

- [Feature lifetime](guides/feature-lifetime.md) for work that survives view changes.
- [Store access coordination](guides/store-access-coordination.md) for writes, restore, and removal.
- [Feature management](guides/feature-management.md), [consent](guides/feature-consent.md), and [data removal](guides/feature-data-removal.md).
- [Owned presentations](guides/feature-owned-presentations.md) and [URL routing](guides/feature-url-routing.md).
- [Database and files](guides/database-files.md), [HTTP](guides/feature-http.md), or [Web storage](guides/web-storage-ownership.md).
- [App Intents](guides/package-app-intents.md), [widgets](guides/package-static-widgets.md), and [incoming files](guides/feature-incoming.md).
- Other Apple system surfaces under [docs/guides](guides/).

A read-only screen does not need dummy lifecycle, backup, or removal providers. Add explicit ownership only for resources and data that exist.

## 5. Keep navigation and app shells separate

The JibunKit host owns the outer `NavigationStack`, the feature list, and the return-to-list action. A feature root view supplies content and may own typed routes or navigation inside its own sheets, but it should not create another host-level stack.

The standalone example app owns its own app shell:

```swift
NavigationStack {
    NotesRootView()
}
```

This keeps the same feature usable independently and inside JibunKit.

## 6. Validate the integration

Run the smallest checks that prove each boundary:

```bash
swift test --package-path Modules/Notes
tuist generate --no-open
tuist build JibunKit-App
```

The Tuist commands require macOS. The package-specific test may run on Linux/WSL only if that feature's dependencies are portable; the repository-root `swift test` currently does not. A WSL installation that already has a compatible Darwin Swift SDK may additionally perform an iOS compile-only check, but that is not an IPA build or a generally installed prerequisite; see the build guide.

Also verify:

1. The standalone example launches and its important behavior works.
2. The integrated host lists exactly one entry and opens it through its stable ID.
3. Data, notifications, tasks, and native registrations do not collide with another feature.
4. Disabling, deleting, restoring, or failing this feature preserves other owners.
5. Package resources and localization load through `Bundle.module`.
6. Any widget, App Intent, extension, entitlement, or background mode is present in the built product.

Compilation, Simulator behavior, installation, physical-device behavior, and live service behavior are separate results. Record what was actually exercised. See [Build, sign, and install](build.md) and [current status](status.md).

## Compatibility checklist

Before publishing an update, review [Compatibility and stable identities](compatibility.md). In particular, do not casually change:

- feature IDs or storage namespaces;
- bundle IDs or App Groups;
- notification request/category IDs;
- widget kinds, App Intent identities, or URL destinations;
- backup schema versions and payload meaning.

The Records module is a larger reference for files, navigation, notifications, and backup integration. See [Records](../Modules/Records/README.md). Focused system-surface details belong in the individual guides rather than in this entry document.

## Troubleshoot package connections

On macOS, run `python3 Tools/check-feature-connection.py --package Modules/Notes --product NotesFeature`. It evaluates the trusted checkout's Swift and Tuist manifests to check the path, library product, target membership and direct host dependency; `--host` selects a different target such as the widget. It does not prove compilation, transitive integration dependencies or runtime registry contents.

Check the first failing boundary in order:

1. Package not found: correct `Project.swift`'s package path and confirm `Modules/Notes/Package.swift` exists.
2. Product not found: match the package's library product and target names; run `swift package --package-path Modules/Notes describe`, package tests and generation.
3. `No such module`: add the product dependency to the exact app or extension target importing it, include integration sources, then regenerate and build.
4. No list entry or URL destination: add the definition once to `MiniAppRegistry.all`; inspect the actual registry IDs with `MiniAppValidator.validate(ids:expectedIDs:)` and exercise `jibunkit://mini-app/notes`.

The expected ID set is a test assertion, not another production registry. Source-text searches alone cannot prove these four connections.
