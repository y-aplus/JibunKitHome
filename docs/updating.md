# Updating the JibunKit foundation

Stable release: 0.8.5/build15. Candidate: 1.0.0/build16, unpublished and awaiting final publication approval. See [status](status.md).

## Keep downstream notes separate

Use `docs-local/` in your personal host repository for migration notes, local decisions and private development procedures. Upstream owns `docs/`; keeping downstream notes elsewhere reduces merge conflicts. Do not submit `docs-local/` in upstream pull requests. The directory name does not make files private: repository visibility controls access. Never commit credentials, signing material or personal application data there. For notes that should remain only on your machine, add the directory to `.git/info/exclude` rather than assuming it is ignored automatically.

Keep your own Features in independent `Modules/<Name>` packages when standalone reuse or Linux/WSL tests of portable logic are useful. The root package is not generally Linux-buildable; test portability depends on the package's actual dependencies. See [Feature setup](mini-apps.md) and [build capabilities](build.md).

JibunKit has no dynamic plug-in mechanism. Features are Swift packages linked into the host at build time.

## Keep ownership boundaries narrow

Place feature logic, storage format, root view, and feature-specific notification scheduling in its package, for example `Modules/<Name>/Sources/<Name>Feature`. Do not add feature screens or notification logic to `Sources/JibunKit`. Normal integration should touch only:

| Integration point | Feature change |
| --- | --- |
| `Project.swift` | Add the package path and app-target product dependency |
| `Package.swift` | If the feature belongs in the root package, add its target/product and test dependencies |
| Integration target or a thin host adapter | Define `MiniAppDefinition` plus storage, backup, and notification wiring |
| `Sources/JibunKit/MiniAppRegistry.swift` | Add one definition to `all` |

Do not add another `NotificationAppDelegate`; route the common payload through the same destination mapping. Add widget/extension products, App Shortcuts, [plist/entitlement requirements](guides/feature-build-requirements.md), and matching verification only for OS surfaces the feature uses. Register background/native startup work through `MiniAppDefinition.onHostLaunch`. See [adding a feature](mini-apps.md).

`JibunKitCore`, root navigation, notification entry points, shared build settings, workflows, and common documentation are foundation-owned. Do not embed personal feature behavior there.

## Update one of two independent packages

Assume `Modules/FeatureA` and `Modules/FeatureB` are independent and only A is changing. Resources with the same file or localization key remain declared in their own targets and are read with `Bundle.module`; do not move A's resource into `Bundle.main` or include B files in the A commit.

Before the update:

1. Start from a clean tree and run each package's standalone tests.
2. In the generated host, record A/B feature IDs, actual same-named resources, required localizations, and stored values. Do not record secrets.
3. Record IDs, product names, and storage namespaces, then commit the baseline.
4. If A changes storage format, export an A-only backup with the current version. Do not substitute a copy of B or the entire shared defaults suite.

Limit the update to FeatureA and its necessary integration. Preserve its ID and storage location. Introduce fields as optional/default values that decode old data, or implement an explicit schema migration. Do not turn corruption into empty data. Coordinate migration/reset through [store access](guides/store-access-coordination.md). Records v1-to-v2 decoding/validation/migration is the small reference implementation. If A owns long-lived tasks or database connections, update [feature lifetime](guides/feature-lifetime.md) and [runtime/restore](runtime-restore-integration.md) too. Leave B's ID, manifest, resources, and storage untouched.

Run:

```bash
swift test --package-path Modules/FeatureA
swift test --package-path Modules/FeatureB
tuist generate --no-open
tuist build JibunKit-App
```

Then verify that both definitions remain in the generated registry. On an upgrade install, verify old A data migrates, new A fields survive reload, each package supplies its own resource/localization, and B data is unchanged. Record package tests, host build, storage behavior, and resource/UI behavior as separate results.

### Recover from a broken FeatureA update

Do not distribute when package tests, generation, host compilation, old-data decoding, or resource comparison fails. For path/product/target/registry errors, use the [feature-addition diagnostics](mini-apps.md#troubleshoot-package-connections). When the A update is one commit and has not shipped, use `git revert <commit>` to preserve history, then rerun both package tests and host generation. Do not broadly restore a dirty tree before preserving unrelated work.

If a device has already begun A's schema migration, do not assume old code can read the new schema. Preserve A data and prefer a forward fix that reads both versions. If a verified backup must be restored, obtain user confirmation and restore only A's provider, then verify A and B. Never guess-delete a package, App Group, or complete defaults suite.

Consent, disable/remove, and owned presentations shipped in 0.7.0. Follow [feature management](guides/feature-management.md), [feature consent](guides/feature-consent.md), [owned-data removal](guides/feature-data-removal.md), and [feature-owned presentations](guides/feature-owned-presentations.md). Restoring a backup must not silently re-enable a removed feature or approve consent.

## Before merging an upstream foundation update

1. Inspect the tree and commit personal changes in meaningful units.
2. Record stored feature values, bundle ID, App Group, and installed version without committing real data or Team IDs.
3. Read the incoming history for storage-key, identifier, minimum-iOS, and build-tool changes.
4. Use `git diff` to identify overlap at the integration points above.

With public upstream named `upstream` and a personal fork named `origin`:

```bash
git status --short
git fetch upstream
git diff HEAD..upstream/main
git merge upstream/main
```

Adapt remote names and merge/rebase policy to the actual repository. Do not create user branches or remotes merely to follow this example.

## Resolve conflicts deliberately

`Package.swift` and `MiniAppRegistry.swift` commonly conflict. Do not choose all of “ours” or “theirs.” Preserve foundation targets/dependencies, personal targets/dependencies, old and new definitions, and unique IDs/namespaces/notification IDs. Keep display names, icons, destinations, bundle ID, App Group, and storage keys unless a separate migration explicitly changes them.

Treat an old unknown notification owner as unknown and return to the list; never guess another feature. Preserve or explicitly migrate old storage even during 0.x development.

## Verify after merging

1. Run Swift tests for ID collisions, App Group resolution, every feature, and isolated storage.
2. Use Tuist/Xcode to compile iOS targets and validate an IPA containing its widget extensions.
3. For Shortcuts, use the Xcode CI path that produces native App Intents metadata.
4. Without deleting the installed app, perform an overwrite installation and verify data, list/screens, Shortcuts, widgets, and notifications.
5. Refresh signing and repeat the same checks.

Separate feature logic, iOS compilation, metadata extraction, re-signing, and device behavior when diagnosing a failure. A build does not prove persistence or system-surface behavior.

The downstream friction log is [2026-09-19-downstream-friction.md](verification/2026-09-19-downstream-friction.md). Treat it as evidence from its recorded environment, not a guarantee for every host, shell, package layout, or signing setup.

## Scope and migrations

This workflow covers source updates and overwrite installation while keeping the same Apple account, bundle IDs, and App Group. Account/Team changes, bundle/App Group changes, reinstall after deletion, and device migration require a separately designed export/import or key migration.

The 2026-09-07 namespace correction preserves built-in `counter`/`reminder` keys and notification IDs. Only string IDs containing a dot encode that dot as `%2E` inside storage namespaces and notification IDs, while retaining the source ID and payload. A downstream build that used the unpublished old encoding must back up, name the feature-owned keys, migrate only those keys, cancel only its old notification IDs, and reschedule under the new IDs. Core cannot safely infer ownership for a bulk migration/deletion.

Since 0.8.1, `Definition.externalAccess` is optional and needed only for another-process writers such as widgets/controls. Existing stores are not forced into `MiniAppSharedState`. Removal/restore increments the storage generation, so old widget/control configurations are rejected until the user reselects a target; see [interactive widgets](guides/interactive-widgets.md). Counter/Reminder IDs and normal IPA composition remain unchanged.
