#if os(iOS)
import XCTest
import UIKit
import JibunKitCore
@testable import JibunKit_App

final class P2ScenesNativeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testRequesterCreatesAndDestroysSecondOSWindowSession() async throws {
        XCTAssertEqual(UIDevice.current.userInterfaceIdiom, .pad, "P2Scenes native target must use an iPad destination")
        let original = Set(P2ScenesOSDiagnostic.connectedWindowSessions)
        XCTAssertFalse(original.isEmpty, "The native host must have a connected UIWindowScene")
        let requester = MiniAppUIKitWindowSceneRequester()
        var requestFailure: Error?
        requester.requestWindow(userActivity: nil) { requestFailure = $0 }
        let createdID = await waitForNewSession(excluding: original, failure: { requestFailure })
        guard let createdID else {
            XCTFail("UIKit did not connect a second window session: \(requestFailure.map(String.init(describing:)) ?? "no explicit error")")
            return
        }

        let secondID = MiniAppWindowSessionID(createdID)

        var destroyFailure: Error?
        XCTAssertTrue(requester.destroyWindow(sessionID: secondID) { destroyFailure = $0 })
        let destroyed = await waitForSessionRemoval(createdID, failure: { destroyFailure })
        XCTAssertTrue(destroyed, "UIKit did not destroy the requested session: \(destroyFailure.map(String.init(describing:)) ?? "no explicit error")")
    }

    @MainActor
    private func waitForNewSession(
        excluding original: Set<String>,
        failure: () -> Error?
    ) async -> String? {
        for _ in 0..<100 {
            if failure() != nil { return nil }
            if let created = Set(P2ScenesOSDiagnostic.connectedWindowSessions).subtracting(original).first {
                return created
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    @MainActor
    private func waitForSessionRemoval(_ id: String, failure: () -> Error?) async -> Bool {
        for _ in 0..<100 {
            if failure() != nil { return false }
            if !P2ScenesOSDiagnostic.connectedWindowSessions.contains(id) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
#endif
