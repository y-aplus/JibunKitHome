# Installing and updating with SideStore

SideStore is an optional, verified installation example for JibunKit. It is not the only supported distribution concept, and this document does not claim that untested signing/install tools preserve the same identifiers, entitlements, data, or extensions.

The currently documented stable release is 0.8.5/build15; candidate 1.0.0/build16 is unpublished and requires final publication approval. Release status is tracked in [status.md](status.md). Historical device observations below belong to their exact source and environment and must not be generalized.

Follow the [official SideStore installation instructions](https://docs.sidestore.io/docs/installation/install) to install SideStore and prepare its pairing file. Connect LocalDevVPN when installing, updating, or refreshing JibunKit.

## Obtain an IPA

For a published release, download the IPA linked by that release rather than an outer Actions ZIP. For a custom feature build, follow [the build guide](build.md) and obtain `JibunKit.ipa` from the successful `JibunKit-ad-hoc` artifact.

Use the current Tuist/Xcode path so the IPA contains native App Intents metadata. The old xtool IPA path is retired. Do not upload an Apple Account password, 2FA code, certificate, or provisioning profile to Actions for this build.

## First installation

1. Connect LocalDevVPN on the iPhone.
2. Open `JibunKit.ipa` in SideStore and sign/install it with the intended Apple account.
3. Launch JibunKit and verify the feature list.
4. Verify Counter persistence and Shortcut/widget behavior plus Reminder notifications. In Backup, test export/import and selected restore; read the selected targets and confirmation before overwrite restore.

When SideStore rewrites App Groups for a personal team, it adds `ALTAppGroups` to the app's `Info.plist`. JibunKit accepts exactly one candidate equal to logical `group.com.jibunkit.shared` or that ID plus SideStore's suffix. Never commit the device/account-specific Team ID.

## Overwrite update

To preserve data, do not delete the current app. Install the new IPA over it and keep:

- app bundle ID: `com.jibunkit.app`
- widget bundle ID: `com.jibunkit.app.Widget`
- App Group: `group.com.jibunkit.shared`
- existing keys: `counter.value` and `reminder.message`

An older differently named app with different bundle/App Group IDs is a separate app and does not migrate automatically into JibunKit.

## Refresh signing

1. Connect LocalDevVPN.
2. Open SideStore's **My Apps**.
3. Tap the remaining-days indicator beside JibunKit.
4. Wait for SideStore to report success.
5. Open JibunKit and recheck stored values and integrations.

The official SideStore instructions describe the same manual refresh gesture. Recheck Counter/Reminder data, widget shared data, the Counter Shortcut, and notification routing after refresh.

## App slots, identifiers, and extensions

JibunKit appears as one app in SideStore's **My Apps** and consumes one active-app slot; SideStore itself also consumes a slot. The [SideStore FAQ](https://docs.sidestore.io/docs/faq) currently explains free-account active-app and App ID limits; treat SideStore/account UI as authoritative because these policies and profile-reuse choices can change.

The normal IPA includes the main app plus widget and Share extensions, with separate bundle IDs including `com.jibunkit.app.Share`. Extensions are not separate home-screen apps, and an App Group is not an app slot. Signing still processes app/extension IDs and profiles, so app-slot count, bundle-ID count, extension count, and App Group count are different concepts. SideStore may offer extension profile reuse; inspect its actual account display rather than deriving an App ID count from this repository.

## Boundaries and troubleshooting

Verified behavior is limited to the source, device, OS, SideStore version, account, and logical IDs recorded in the linked evidence. It does not guarantee every release's first install, overwrite, or refresh, and does not cover:

- changing Apple account or Team;
- changing bundle IDs or App Group;
- deleting and reinstalling JibunKit;
- replacing the device, updating iOS, or rebuilding the pairing file.

SideStore notes that iOS updates or device resets can invalidate the pairing file. Before deleting the app during recovery, consult [SideStore troubleshooting](https://docs.sidestore.io/docs/troubleshooting) and preserve feature data when possible.

When overwriting a diagnostic build with a normal IPA under the same bundle ID, diagnostic features disappear from the app list. A previously placed diagnostic widget can retain stale display after its kind/resources are absent; that is not evidence that its feature or store is still running. Remove the stale widget manually. Code removal and owned-data deletion are separate; see [removing a static widget type](guides/package-static-widgets.md#widget型を出荷構成から除いた後).

## Evidence history

- iPhone 16e / iOS 26.6 / SideStore 0.6.3 verified 0.1.0 build 1→2 overwrite and refresh; see the [0.1 record](verification/0.1.md).
- Source `afbf4dc` verified the Records-connected build, overwrite, refresh, widget/Shortcuts/notifications, and selected restore on 2026-09-09. Its device/OS/SideStore version was not re-reported; do not copy the older environment onto it. See the [candidate record](verification/2026-09-09-v1-candidate.md).
- Sources `6beb877` and `4e6a3f4` provide component-specific 0.8.0-era device evidence. The published 0.8.0/build10 IPA was checked for CI, version/IDs, signing structure, CRC, and release-download integrity, but that exact IPA did not receive a new device run. See the [release record](verification/2026-09-15-0.8-release.md), [P1-A record](verification/2026-09-13-p1-a.md), and [P1 device procedure](verification/2026-09-14-0.8-device-check.md).

Those historical observations establish only the tested SideStore path. Other installation or re-signing methods remain unverified unless their own evidence says otherwise.
