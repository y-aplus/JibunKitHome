# Widget localization

The normal Counter Widget keeps its stable `JibunKitCounterWidget` kind, timeline provider, deep link, and owner-scoped storage. Only its user-facing copy is localized.

Runtime Widget views and the gallery name and description resolve keys from `Localizable.strings` in the Widget extension target. While WidgetKit runs the extension, `Bundle.main` is the `.appex` bundle, not the containing app bundle. Therefore the production resource glob must include `Sources/JibunKitWidget/Resources/**` in `JibunKitWidget-Extension`; adding these files only to the app target does not localize the Widget.

The native localization test must be hosted by the built app and depend on its Widget extension. It locates the sibling production `.appex` under the host's `PlugIns` directory, verifies its bundle identifier, opens its actual `en.lproj` and `ja.lproj`, and checks every runtime status and gallery key. It deliberately does not inject a fixture bundle into `CounterWidgetCopy`, because that could pass while the shipped extension omitted its resources.

The native bundle test proves packaged strings and lookup inputs. It does not prove that the OS Widget gallery or a home-screen Widget rendered the selected language. CI35347692100 at `18a94bd` separately verified the actual SpringBoard Counter gallery name/description, preview OCR and home-screen title in English on an iPad (A16) iOS26.5 Simulator. This is OS-rendered evidence, not a physical-device test or a complete language/state matrix. English/Japanese resource completeness and state copy remain covered by the built-extension tests; unchanged value-update and ownership evidence is reused. Repeating every language/state combination manually is not required by the adopted scope.
