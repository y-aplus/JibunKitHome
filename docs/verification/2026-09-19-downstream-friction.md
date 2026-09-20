# Downstream migration feedback: v1 documentation follow-up

Source: [JibunKitHome friction log](https://github.com/y-aplus/JibunKitHome/blob/68b4f096d130ecf945726418d836a5aa8dcb14f3/docs-local/friction-log.md), supplied by the owner on 2026-09-19. The experiment used JibunKit0.8.3 and a non-Codex AI agent to integrate Zaiko using published documentation. This is observed downstream friction, not authorization to change the downstream repository or import private Zaiko sources.

| Item | Publication-preparation response |
|---|---|
| F-001 private downstream initialization | Entry-doc worker: explicit clone and upstream/origin setup; distinguish private independent repository from public fork |
| F-002 initial app identities | Entry-doc worker: explain replacing an existing installation versus creating a separately identified app; avoid implicit data migration promises |
| F-003 inherited workflow | Entry-doc worker: describe existing default-build evidence35237198657, contents:read and absence of secrets usage; do not imply unrun optional filters passed |
| F-004 package placement | Entry-doc worker: independent Modules default for standalone reuse/portable tests; root choice and platform dependencies explicit |
| F-005 downstream notes | Parent: recommend docs-local, explain visibility and local-only exclusion; no credentials or personal payloads |
| F-006 compile-only SDK route | Entry-doc worker: document reported preconfigured Darwin SDK compile-only experiment separately from IPA production; do not imply SDK availability or Xcode-equivalent verification |
| F-007 Linux root tests | Entry-doc worker: remove unconditional root swift-test claim; independent portable package tests remain distinct |
| F-008 platform matrix | Entry-doc worker: show local tasks versus macOS/Xcode CI; reported Linux Tuist4.207 installation does not establish local generate/scaffold support |
| F-009 CLI target ambiguity | Entry-doc worker: explicit --repo OWNER/HOST in downstream workflow examples; do not depend on implicit gh remote selection |

The upstream workflow source currently declares contents:read, uses artifact upload and contains no secrets references. The downstream run is user-supplied evidence and has not been independently reproduced here. The documented SDK experiment must remain scoped to its configured environment. These tasks amend onboarding and build documentation; they do not reopen the accepted functional v1 scope or claim a root Linux port.

Status: F-005 text added; remaining entry/build changes assigned for one consolidated review. No downstream files or settings changed. Final completion requires reviewing the resulting instructions, links and examples, not merely adding English headings.


## Critical assessment before adopting recommendations

- F-007 is supported by current source: root Package.swift supports Apple targets and depends on JibunKitCore; MiniAppNetworkCache/MiniAppWebData import CryptoKit and incoming/notification paths call security-scoped URL APIs. Remove the unconditional Linux root-test promise. This inspection is not a new Linux execution result, and merely moving a Feature into Modules does not make Apple-dependent code portable.
- F-008's distinction is supported by [Tuist installation documentation](https://tuist.dev/en/docs/guides/install-tuist): the CLI runs on Linux, but Xcode-dependent generation is unavailable there. Do not generalize the report's exact subcommand list to every future version.
- F-006 is a reported configured-SDK experiment, not a standard installation path. Compilation does not validate metadata extraction, signing, extensions or runtime behavior. Preserve a conditional reference instead of reinstating the retired xtool IPA route or promising that a Swift installation includes a Darwin SDK.
- F-001/F-002/F-005 are onboarding choices. A private downstream repository is a useful option, not a requirement for every developer. Maintaining identifiers applies to an existing installation; a separate app must deliberately choose its own identity and sharing policy. docs-local is an organizational convention, not a privacy boundary.
- F-003 is narrower than a full downstream CI guarantee. Current workflow inspection confirms read-only repository permission and no secrets references; optional configurations remain separately evidenced. F-009's explicit repository argument removes ambiguity without changing users' global CLI settings.

No downstream implementation, SDK installation, repository visibility or CLI settings were changed by this review.
