# File picker comparison fixture

This diagnostic app separates Files provider materialization from JibunKit backup parsing and state. It exports one fixed JSON file through UIKit, then offers two opening routes for that same file:

- SwiftUI `fileImporter`
- UIKit `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: false)` as the primary same-semantics comparison
- UIKit `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: true)` as a separately labelled copy comparison

Every route records URL callback arrival before reading. It then requires the complete bytes to equal the fixed fixture, rather than accepting only a filename or length. Results appear in `picker.status` and under subsystem `com.jibunkit.file-picker-comparison`, category `Picker`. The fixture does not import `JibunKitCore`, `JibunKitBackup`, or the production `BackupScreen`.

The dedicated `FilePickerComparisonUITests` scheme uses a fresh simulator, saves `JibunKit-picker-comparison.json` under **On My iPhone**, selects that exact name with native open, relaunches, and selects it with SwiftUI. A native failure does not suppress the later SwiftUI attempt. Interpret the result narrowly:

- neither picker delegate/completion receives a URL and OS logs show FileProvider `-1005` / resolver `-1012`: provider preparation/materialization fails before either app bridge;
- UIKit succeeds but SwiftUI does not: isolate the SwiftUI bridge path;
- both succeed: the failure needs the original BackupHarness export/provider history or runner state; this fixture does not clear the production screen;
- a URL arrives but reading fails: inspect security-scope/copy semantics separately.

This is a diagnostic fixture, not evidence that the production JSON or ZIP restore completed.
