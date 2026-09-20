# Contributing to JibunKit

Thank you for improving JibunKit. This document is for changes to the framework, host, templates, tests, and project documentation. If you only want to add a feature to your own build, start with [Adding a feature](docs/mini-apps.md).

## Before you change code

1. Read the [current status](docs/status.md), [coexistence boundaries](docs/coexistence-boundaries.md), and [compatibility policy](docs/compatibility.md).
2. Search existing issues. Use a GitHub issue for a bug or proposal; discuss large contract changes before implementing them.
3. Keep one branch and pull request focused on one purpose.
4. Never commit credentials, Apple account data, signing keys, certificates, provisioning profiles, pairing files, Team IDs, device identifiers, real user data, or Apple SDK files.

Report vulnerabilities privately according to [SECURITY.md](SECURITY.md), not in a public issue.

## Design rules

- Keep feature-specific behavior in the feature. Add shared infrastructure only when integration genuinely requires shared ownership, isolation, or arbitration.
- Preserve stable IDs, storage namespaces, bundle IDs, App Groups, notification routes, widget kinds, App Intent identities, and backup schemas. If a change is unavoidable, include a migration and describe its user impact.
- Keep feature APIs owner-scoped. Stopping, disabling, deleting, or failing one feature must not silently change another feature's state.
- Treat cancellation and shutdown as completion boundaries. Shared native resources are not available to a new owner until the old owner has actually released them.
- Do not describe unit tests, injected callbacks, Simulator runs, physical-device runs, and live Apple-service results as interchangeable evidence.
- Do not broaden a verified claim beyond its tested OS, device, signing, radio, account, or service conditions.

The focused contracts under [docs/guides](docs/guides/) and the [coexistence ledger](docs/coexistence-ledger.md) contain the detailed rules for individual system surfaces.

## Build and test

Run the root package tests on macOS. The root `JibunKitCore` package currently uses Apple-specific APIs and does not build on Linux/WSL, so merely having Swift installed there is not sufficient:

```bash
swift test
```

An independent package under `Modules/` may support local Linux/WSL tests when its own dependencies are portable. Test it explicitly with `swift test --package-path Modules/NAME`; do not infer root-package support from that result.

iOS builds and Apple-framework tests require macOS and Xcode, or the repository's GitHub Actions workflows:

```bash
tuist generate --no-open
xcodebuild build \
  -workspace JibunKit.xcworkspace \
  -scheme JibunKit-App \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

See [Build, sign, and install](docs/build.md) for pinned versions, CI inputs, artifacts, and verification boundaries.

Choose tests in proportion to the change:

- Run package tests for shared logic and feature behavior.
- Generate the workspace after changing Tuist manifests, targets, extensions, resources, entitlements, or build settings.
- Exercise the standalone example and integrated host when changing a feature template or integration contract.
- Use the relevant native or UI diagnostic for Apple system behavior. Do not replace required physical or service-backed evidence with a fake callback.
- For documentation-only changes, validate local links, commands, filenames, and release-state wording.

Maintainers group expensive CI at reviewed boundaries. A contributor should report what was run and what remains unverified, rather than starting every workflow for every small commit.

## Pull requests

Include:

- the problem and why the change belongs in JibunKit;
- the contract and compatibility impact;
- the tests or inspections performed;
- any unverified device, OS, signing, radio, account, or service condition;
- user-facing documentation when behavior changes.

The current stable version is 1.0.0. Keep release claims tied to the published tag and its source-specific verification; historical candidate records remain dated evidence.

Maintainers review design fit, compatibility, isolation between owners, automated evidence, and any necessary device evidence separately. A successful build proves compilation; it does not by itself prove installation, migration, background delivery, radio behavior, or a live Apple service.
