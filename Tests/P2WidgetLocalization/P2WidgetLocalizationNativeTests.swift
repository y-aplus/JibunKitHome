#if os(iOS)
import Foundation
import XCTest

final class P2WidgetLocalizationNativeTests: XCTestCase {
    private let expected: [String: [String: String]] = [
        "en": [
            "counter.title": "Counter",
            "counter.status.removed": "Removed",
            "counter.status.disabled": "Disabled",
            "counter.status.stopped": "Stopped",
            "counter.status.unavailable": "Unavailable",
            "counter.gallery.name": "Counter",
            "counter.gallery.description": "Shows the value updated by the app and shortcuts.",
        ],
        "ja": [
            "counter.title": "カウンター",
            "counter.status.removed": "削除済み",
            "counter.status.disabled": "無効",
            "counter.status.stopped": "停止中",
            "counter.status.unavailable": "読取不可",
            "counter.gallery.name": "カウンター",
            "counter.gallery.description": "アプリとショートカットが更新した値を表示します。",
        ],
    ]

    func testBuiltWidgetExtensionContainsEveryLocalizedRuntimeAndGalleryString() throws {
        let widget = try builtWidgetBundle()
        XCTAssertEqual(widget.bundleIdentifier, "com.jibunkit.app.Widget")

        for (language, values) in expected {
            let localizationURL = try XCTUnwrap(
                widget.url(forResource: language, withExtension: "lproj"),
                "Missing \(language).lproj in built Widget extension"
            )
            let localizedBundle = try XCTUnwrap(Bundle(url: localizationURL))
            for (key, value) in values {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    value,
                    "Unexpected \(language) Widget value for \(key)"
                )
            }
        }
    }

    private func builtWidgetBundle() throws -> Bundle {
        // A host-attached native test bundle is nested at
        // Host.app/PlugIns/Test.xctest. Resolve the sibling production appex;
        // never fall back to this test bundle's copied fixtures.
        let testBundle = Bundle(for: Self.self).bundleURL
        let hostApp = testBundle.deletingLastPathComponent().deletingLastPathComponent()
        let plugins = hostApp.appendingPathComponent("PlugIns", isDirectory: true)
        let candidates = try FileManager.default.contentsOfDirectory(
            at: plugins,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "appex" }
        let matches = candidates.compactMap { Bundle(url: $0) }.filter {
            $0.bundleIdentifier == "com.jibunkit.app.Widget"
        }
        return try XCTUnwrap(matches.only, "Expected one built JibunKit Widget extension in \(plugins.path)")
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}
#endif
