#if os(iOS)
import JibunKitCore
import SwiftUI
import UIKit
import XCTest
@testable import JibunKit_App

@MainActor
final class P2AppearanceNativeTests: XCTestCase, @unchecked Sendable {
    func testNormalDefinitionsDriveIndependentSceneIdleRequests() async throws {
        var nativeChanges: [Bool] = []
        let timer = MiniAppIdleTimer { nativeChanges.append($0) }
        let a = P2AppearanceFeature(id: MiniAppID("appearance-test-a"), title: "A", scheme: .dark, timer: timer)
        let b = P2AppearanceFeature(id: MiniAppID("appearance-test-b"), title: "B", scheme: .light, timer: timer)
        try await a.lifetime.start(); try await b.lifetime.start()
        let scenes = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: a.id) { a.receive($0) }, .init(id: b.id) { b.receive($0) },
        ])
        scenes.connect(phase: .active, selectedID: a.id)
        a.setRequested(true); b.setRequested(true)
        XCTAssertTrue(a.requested && a.effective)
        XCTAssertTrue(b.requested && !b.effective)
        scenes.update(phase: .active, selectedID: b.id)
        a.refreshEffective(); b.refreshEffective()
        XCTAssertTrue(a.requested && !a.effective)
        XCTAssertTrue(b.requested && b.effective)
        scenes.update(phase: .background, selectedID: b.id)
        b.refreshEffective()
        XCTAssertFalse(b.effective)
        XCTAssertEqual(nativeChanges, [true, false, true, false])
        await a.lifetime.stop(); await b.lifetime.stop()
    }

    func testEnvironmentOverrideChangesSwiftUIReadingWithoutClaimingUIKitTrait() async throws {
        let feature = P2AppearanceFeature(id: MiniAppID("appearance-env"), title: "Environment", scheme: .dark)
        let host = UIHostingController(rootView: P2AppearanceRoot(feature: feature, policy: .environment(.dark)))
        let windows = try WindowHarness()
        defer { windows.cleanup() }
        let window = windows.mount(host, style: .light)
        let rootObserved = await waitUntil { feature.rootEnvironment == "dark" && feature.rootTrait != "unread" }
        XCTAssertTrue(rootObserved)
        XCTAssertEqual(feature.rootEnvironment, "dark")
        XCTAssertEqual(window.traitCollection.userInterfaceStyle, .light)
        // The embedded UIKit trait is recorded separately; it is not assumed to
        // follow a SwiftUI environment override.
        XCTAssertNotEqual(feature.rootTrait, "unread")
        feature.showingSheet = true
        let sheetObserved = await waitUntil { feature.sheetEnvironment == "dark" && feature.sheetTrait != "closed" }
        XCTAssertTrue(sheetObserved)
        XCTAssertEqual(feature.sheetEnvironment, "dark")
        XCTAssertNotEqual(feature.sheetTrait, "closed")
    }

    func testPreferredSchemeAffectsItsPresentationButNotAnotherWindow() async throws {
        let a = P2AppearanceFeature(id: MiniAppID("appearance-preferred-a"), title: "A", scheme: .dark)
        let b = P2AppearanceFeature(id: MiniAppID("appearance-preferred-b"), title: "B", scheme: .light)
        let aHost = UIHostingController(rootView: P2AppearanceRoot(feature: a, policy: .preferred(.dark)))
        let bHost = UIHostingController(rootView: P2AppearanceRoot(feature: b, policy: .preferred(.light)))
        let windows = try WindowHarness()
        defer { windows.cleanup() }
        let aWindow = windows.mount(aHost, style: .light)
        let bWindow = windows.mount(bHost, style: .dark)
        let rootsObserved = await waitUntil { a.rootEnvironment == "dark" && b.rootEnvironment == "light" }
        XCTAssertTrue(rootsObserved)
        XCTAssertEqual(a.rootEnvironment, "dark")
        XCTAssertEqual(b.rootEnvironment, "light")
        XCTAssertEqual(aHost.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(bHost.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(aWindow.rootViewController?.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(bWindow.rootViewController?.traitCollection.userInterfaceStyle, .light)
        a.showingSheet = true
        let sheetObserved = await waitUntil { a.sheetEnvironment == "dark" && a.sheetTrait == "dark" }
        XCTAssertTrue(sheetObserved)
        XCTAssertEqual(a.sheetEnvironment, "dark")
        XCTAssertEqual(a.sheetTrait, "dark")
        XCTAssertEqual(b.rootEnvironment, "light")
    }

    func testContainedUIKitControllerOverrideDoesNotChangeSiblingOrWindow() throws {
        let windows = try WindowHarness()
        defer { windows.cleanup() }
        let parent = UIViewController()
        let dark = P2ContainedAppearanceViewController(style: .dark)
        let inherited = P2ContainedAppearanceViewController(style: .unspecified)
        parent.addChild(dark); parent.view.addSubview(dark.view); dark.didMove(toParent: parent)
        parent.addChild(inherited); parent.view.addSubview(inherited.view); inherited.didMove(toParent: parent)
        let window = windows.mount(parent, style: .light)
        XCTAssertEqual(dark.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(inherited.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(window.traitCollection.userInterfaceStyle, .light)
    }

    func testSamePresentationSwitchesEnvironmentToPreferenceAndBackWithoutLeak() async throws {
        let a = P2AppearanceFeature(id: MiniAppID("appearance-switch-a"), title: "A", scheme: .dark)
        let b = P2AppearanceFeature(id: MiniAppID("appearance-switch-b"), title: "B", scheme: .light)
        let selection = P2AppearanceSelection()
        let host = UIHostingController(rootView: P2AppearanceSwitchingRoot(
            selection: selection, first: a, second: b
        ))
        let windows = try WindowHarness()
        defer { windows.cleanup() }
        _ = windows.mount(host, style: .dark)
        let firstObserved = await waitUntil { a.rootEnvironment == "dark" && a.rootTrait == "dark" }
        XCTAssertTrue(firstObserved)

        selection.selected = .second
        let secondObserved = await waitUntil { b.rootEnvironment == "light" && b.rootTrait == "light" }
        XCTAssertTrue(secondObserved)
        b.showingSheet = true
        let sheetObserved = await waitUntil { b.sheetEnvironment == "light" && b.sheetTrait == "light" }
        XCTAssertTrue(sheetObserved)
        b.showingSheet = false
        let dismissed = await waitUntil { host.presentedViewController == nil }
        XCTAssertTrue(dismissed)

        a.resetAppearanceReadings()
        selection.selected = .first
        let revisited = await waitUntil { a.rootEnvironment == "dark" && a.rootTrait == "dark" }
        XCTAssertTrue(revisited)
        XCTAssertEqual(a.rootEnvironment, "dark")
        XCTAssertEqual(b.rootEnvironment, "light")
        XCTAssertNil(host.presentedViewController)
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}

@MainActor
private final class WindowHarness {
    private let originalKeyWindow: UIWindow?
    private let scene: UIWindowScene
    private var windows: [UIWindow] = []

    init() throws {
        scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
    }

    func mount<Content: View>(_ host: UIHostingController<Content>, style: UIUserInterfaceStyle) -> UIWindow {
        mount(host as UIViewController, style: style)
    }

    func mount(_ controller: UIViewController, style: UIUserInterfaceStyle) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        windows.append(window)
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return window
    }

    func cleanup() {
        for window in windows.reversed() {
            window.isHidden = true
            window.rootViewController = nil
        }
        windows.removeAll()
        originalKeyWindow?.makeKey()
    }
}
#endif
