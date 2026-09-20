# Security policy

## Supported scope

We consider fixes for the latest published release and `main`. Identify an unpublished candidate by commit. This is an experimental personal project with no guaranteed response or fix deadline.

Report problems caused by JibunKit source, workflows, generated IPAs or bundle/App Group configuration. Report problems in iOS, Xcode or an installer to its provider; incorrect use or configuration by JibunKit remains in scope.

## Report privately

Do not post vulnerability details in public issues, pull requests or discussions. Use [GitHub private vulnerability reporting](https://github.com/y-aplus/JibunKit/security/advisories/new). Collaborators can use a draft security advisory. If private reporting is unavailable, open an issue saying only that the private reporting channel is unavailable.

Include the affected version/commit, reproduction conditions, expected and actual behavior, impact and minimal steps. Do not attach Apple account data, two-factor codes, tokens, signing keys, certificates, provisioning profiles, pairing files, Team IDs, device identifiers or real user content.

## Distribution boundaries

- The standard Actions build receives no Apple credentials or personal signing material. It produces an ad-hoc-signed IPA that still needs valid device provisioning and signing through the chosen installation method; SideStore is one tested example.
- External Actions are pinned to reviewed commits.
- Workflows inspect tracked files for credential, signing, pairing, SDK and IPA material before producing artifacts.
- Reminder text is stored in UserDefaults and appears in local notifications. Do not use it to store secrets.
- Feature namespaces coordinate trusted source code; they are not a security sandbox against malicious code within the same process.

See [release procedures](docs/releasing.md) for publication checks.
