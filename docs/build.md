# Build, sign, and install

The supported path is **source configuration → Tuist/Xcode build → signing → installation**. JibunKit does not depend on one installer.

The verified build configuration uses Swift 6, Tuist 4.207.0, Xcode 26.6, and an iOS 26 deployment target. Generated Xcode projects, workspaces, and Derived Data are outputs; do not edit or commit them.

## Source ownership

- `Package.swift` defines shared libraries, feature products, integrations, and package tests.
- `Project.swift` composes the app, extensions, examples, UI tests, Info.plist values, and build settings.
- `Tuist/Templates/feature` contains the standalone feature template.
- Entitlement files declare App Groups and capabilities for each executable target.

Read [Adding a feature](mini-apps.md) before changing package products or host registration.

## Create a private derived host

Keep personal features in a private repository with two explicit remotes: `upstream` for public JibunKit and `origin` for your private host. One initial setup is:

```bash
git clone https://github.com/y-aplus/JibunKit.git PRIVATE_HOST
cd PRIVATE_HOST
git remote rename origin upstream
git remote add origin git@github.com:OWNER/PRIVATE_HOST.git
git push -u origin main
gh repo set-default OWNER/PRIVATE_HOST
```

Create `OWNER/PRIVATE_HOST` as a private repository before the push. Replace the example branch if your derived host uses another default branch. Do not use a public fork when the repository will contain private features or configuration.

Before the first install, choose the identity strategy deliberately:

- To update an existing JibunKit installation in place and retain its shared data, preserve its bundle IDs and App Group and use the same compatible signing account.
- To install an independent app alongside it, assign new bundle IDs and a new App Group consistently to the app and every extension. It will not share the existing app's container.

Changing these values later is a compatibility and data-migration decision, not cosmetic renaming.

## Local macOS build

Select the verified Xcode version and install the pinned Tuist version, then run:

```bash
swift test
tuist generate --no-open
xcodebuild build \
  -workspace JibunKit.xcworkspace \
  -scheme JibunKit-App \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
```

`CODE_SIGNING_ALLOWED=NO` verifies the unsigned build. To run on a device, configure a development team and valid capabilities in Xcode, build the app, and let Xcode sign and install it. App Groups, extensions, background modes, CloudKit, APNs, and similar services require matching identifiers, entitlements, profiles, and account capabilities.

The `CounterExample` scheme is a small standalone reference. A generated feature has its own example workspace and scheme; develop there before integrating it into the host.

## GitHub Actions build

From any machine with Git and GitHub CLI access, push a branch and run:

```bash
gh workflow run build-ios.yml \
  --repo OWNER/PRIVATE_HOST \
  --ref YOUR_BRANCH \
  -f simulator_tests=true \
  -f feature_validation=true
```

Always pass `--repo OWNER/PRIVATE_HOST` (or first set that repository with `gh repo set-default`). With both `origin` and `upstream`, an implicit selection can target the public upstream repository.

The workflow installs the pinned Tuist binary, runs the selected Swift and Simulator checks, builds the app and extensions with Xcode, validates metadata and identifiers, and packages an ad-hoc IPA. Download the `JibunKit-ad-hoc` artifact from that run.

In one derived-host experiment, the default workflow inputs completed as run `35237198657` (`Xcode 26.6 (combined)`), including IPA packaging and inspection. That run used no repository secrets and only `permissions: contents: read`. It did **not** run the additional `simulator_tests`, `feature_validation`, or native-comparison inputs, so it is not evidence for those paths or for every derived repository.

The flags select additional work; they are not universal proof of every surface:

- `feature_validation=true` checks the generated template, its standalone app, host composition, and, when `records_validation=true`, the Records reference feature.
- `simulator_tests=true` enables the configured Simulator UI checks.
- Focused and native-surface workflows are diagnostics for named boundaries. Their success does not imply that the full release suite ran.

Use the workflow inputs, completed steps, test summaries, and artifacts as the exact record of what was verified. The CI policy and evidence grouping are documented in [CI boundaries](ci-boundaries.md).

## What can run locally

| Environment | Supported local work | Important limit |
| --- | --- | --- |
| macOS with Xcode and Tuist 4.207.0 | Root tests, feature tests, scaffold, project generation, Xcode build, Simulator, and local signing/install | Capabilities still depend on the signing account, profiles, device, and services. |
| Windows | Source editing and Git/GitHub CLI operations | Use macOS or Actions for project generation, Xcode builds, and IPA packaging. |
| Linux/WSL with Swift | Tests for a portable independent package, for example `swift test --package-path Modules/Notes` | The root package does not currently build on Linux/WSL. |
| Linux/WSL with the tested Tuist 4.207.0 binary | Installation and `tuist version` worked in the reported experiment | In that experiment, its command set did not provide the local `tuist scaffold` or Xcode-project `tuist generate` path used by this repository. Do not generalize this result to other Tuist versions. |

An additional, environment-specific compile-only path was measured on WSL where a Darwin Swift SDK was already installed: `swift build --package-path Modules/Zaiko --swift-sdk arm64-apple-ios` compiled the feature's iOS-gated code. This can catch type errors, but it neither generates an Xcode project nor creates an IPA. JibunKit does not bundle or install that SDK, and this observation does not imply that a standard WSL Swift installation has it. Check `swift sdk list` first and treat SDK setup as outside the supported first-use path.

## Sign and install

An unsigned app cannot run on a normal device. Choose a signing and installation path that fits your Apple account and environment:

- Xcode can sign and install a local build on a connected device.
- An organization may use its own supported distribution process.
- SideStore can sign and install a compatible IPA and is the path used for some JibunKit device checks. See the [SideStore example](sidestore.md).

SideStore is an example, not part of JibunKit and not a prerequisite for the source project. Follow the installer's own current documentation. Do not commit signing material or account credentials to this repository.

Free and paid Apple accounts expose different capabilities and provisioning lifetimes. A successful ad-hoc package, Xcode build, or Simulator run does not prove that every entitlement can be signed or used by a chosen account. CloudKit and APNs are optional in JibunKit 1.0 scope and their live service paths remain unverified.

## Verification boundaries

Keep these results separate:

1. Swift/package tests.
2. Xcode compilation and metadata generation.
3. Simulator system behavior.
4. Signing and installation.
5. Physical-device behavior.
6. Live radio, account, or Apple-service behavior.

The current stable release is 1.0.0/build16. Consult [current status](status.md), the [remaining observation boundary](verification/2026-09-19-final-observation-boundary.md), and the relevant dated verification record before making a release claim.
