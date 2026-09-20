#if os(iOS)
import CloudKit
import XCTest
@testable import JibunKitCore

/// Compile only in the separately signed CloudKit test target. This source is
/// intentionally outside Tests/P2Identity so the ordinary diagnostic host has no skip.
final class P2IdentitySignedCloudKitTests: XCTestCase {
    func testEntitledCloudKitRoundTrip() async throws {
        let identifier = try XCTUnwrap(ProcessInfo.processInfo.environment["JIBUNKIT_CLOUDKIT_CONTAINER"])
        let container = CKContainer(identifier: identifier)
        let scope = try MiniAppExternalContainer(identifier: identifier)
        let coordinator = MiniAppExternalIdentityCoordinator(
            owner: MiniAppID("p2-native-cloudkit"), container: scope,
            backend: CloudKitExternalIdentityBackend(container: container))
        _ = try await coordinator.activate()
        let record = try await coordinator.identity(localID: "signed-roundtrip")
        let nonce = UUID().uuidString
        try await coordinator.save(record, fields: ["nonce": nonce, "preserved": "yes"])
        try await coordinator.save(record, fields: ["nonce": nonce + "-updated"])
        let fetched = try await coordinator.load(record)
        XCTAssertEqual(fetched?.fields["nonce"], nonce + "-updated")
        XCTAssertEqual(fetched?.fields["preserved"], "yes")
        try await coordinator.delete(record)
    }
}
#endif
