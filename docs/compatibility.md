# Compatibility and Feature responsibilities

Stable release: **1.0.0/build16**. The 1.0.0 artifact was published after the owner accepted its functional criteria and the final audit completed. See [current status](status.md), [release verification](verification/2026-09-19-1.0-release.md), and [explicitly unobserved conditions](verification/2026-09-19-final-observation-boundary.md).

## Coexistence contract

When integration into JibunKit removes isolation, coordination or ownership that a standalone app would obtain from the OS or app boundary, JibunKit compensates for that difference where feasible. Separate modules and shared APIs alone are insufficient: contention, cancellation, shutdown and restoration must preserve the intended owner. See [coexistence boundaries](coexistence-boundaries.md).

Feature namespaces are cooperative isolation, **not a security sandbox**. Features execute in one process with shared signing privileges. They must not read or mutate another Feature's data outside an explicit shared contract. JibunKit does not load arbitrary compiled IPAs.

## Stable identities and data

A Feature ID is persistent identity, independent of its display name. Renaming a screen must not rename its ID. Counter/Reminder IDs, storage keys and existing notification request IDs are retained. Changes to identity or storage location require migration, recovery after partial failure, and update-install verification.

API and data compatibility applies to every version, including 0.x. A version bump alone does not justify breakage. Public API removal or signature changes require an explicit migration explanation and consideration of a deprecation period.

## Supported integration boundaries

- Register `MiniAppDefinition` values in the registry; do not add Feature-specific switches to host navigation or lists.
- A standalone Feature may depend on Core or receive storage/services/entry points from an integration adapter.
- Use public IDs, context, storage, backup providers and URL generation. Host view types, diagnostic applications and temporary CI source transformations are not public APIs.
- Prefer additive APIs and optional registrations. Complex Features remain responsible for their own domain logic; JibunKit does not require a simple-screen-only architecture.

## Backup compatibility

The outer `JibunKitBackup` version 1 and each entry's `schemaVersion` are separate versions. New formats and file-backed paths must preserve existing version-1 input. Unknown formats must not be guessed as known ones.

Features own payload schemas, migrations, validation and application. Preparation must not mutate live data or notifications. Validate migrated state before returning an apply operation. Corrupt input must not produce a partially applied state reported as success.

Restore across all Features is not atomic. Report applied, failed and unattempted targets separately. Feature-local rollback follows that Feature's transaction design. Copying an open database file is not automatically a consistent snapshot.

## System surfaces

Features own notification scheduling conditions, rescheduling and cancellation; Core supports owner IDs and routing. Declare Widget/App Intents permissions and entitlements in the app/extension integration layer. Registering a Feature alone does not enable every OS capability.

`jibunkit://mini-app/<ID>` opens an entry; it does not mutate data or invoke arbitrary operations. Optional destination queries preserve this existing URL contract. Integration validates detailed identifiers and converts them into navigation values; the host does not interpret Feature-specific types or guess another owner for unknown URLs.

`Definition.externalAccess` remains optional. Use its owner-scoped shared-state and management/restore coordination when another process, such as a Widget or Control, writes data. Existing databases need not migrate to `MiniAppSharedState`. Removal/restore advances the stored generation: old Widget/Control configurations reject updates until their target is selected again. See [interactive widgets](guides/interactive-widgets.md).

## Signing and verification limits

Signing entitlements, app-group access, OS scheduling and device capabilities remain platform constraints. CloudKit/APNs are optional, conditional integrations with live service communication unverified; they are not required for normal free-signing use. Generic HTTP synchronization remains part of the normal ownership contract.

Preserve the distinction between physical-device observations, Simulator OS execution and injected native contract tests. The accepted [unobserved conditions](verification/2026-09-19-final-observation-boundary.md) are not successes. The installation tool is chosen by the developer; tested SideStore behavior does not prove every other signing path.

For API/storage changes, check older data, standalone and integrated builds, other-owner preservation and affected UI. Reuse unchanged source-specific device evidence when justified by reviewed differences; do not claim a new device run for a candidate that was only rebuilt with updated version metadata.
