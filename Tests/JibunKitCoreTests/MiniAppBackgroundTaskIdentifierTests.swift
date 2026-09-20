import XCTest
@testable import JibunKitCore

final class MiniAppBackgroundTaskIdentifierTests: XCTestCase {
    private let original = "com.example.host"
    private let installed = "com.example.host.TESTSIGNER"

    func testRewrittenManifestMapsOrdinarySharedAndBothContinuedOwners() {
        let suffixes = [".a.ordinary", ".b.ordinary", ".shared-refresh", ".a.export.*", ".b.export.*"]
        let info: [String: Any] = ["JibunKitOriginalBundleIdentifier": original,
            "CFBundleIdentifier": installed,
            "BGTaskSchedulerPermittedIdentifiers": suffixes.map { installed + $0 }]
        for suffix in [".a.ordinary", ".b.ordinary", ".shared-refresh", ".a.export.job1", ".b.export.job2"] {
            XCTAssertEqual(MiniAppBackgroundTaskIdentifier.resolve(original + suffix, info: info), installed + suffix)
        }
        XCTAssertEqual(MiniAppBackgroundTaskIdentifier.resolve(installed + ".a.ordinary", info: info), installed + ".a.ordinary")
    }

    func testUnchangedManifestAndExternalNamespacesStayUnchanged() {
        let identifier = original + ".a.ordinary"
        XCTAssertEqual(MiniAppBackgroundTaskIdentifier.resolve(identifier, info: [:]), identifier)
        let info: [String: Any] = ["JibunKitOriginalBundleIdentifier": original,
            "CFBundleIdentifier": installed, "BGTaskSchedulerPermittedIdentifiers": [identifier]]
        XCTAssertEqual(MiniAppBackgroundTaskIdentifier.resolve(identifier, info: info), identifier)
        XCTAssertEqual(MiniAppBackgroundTaskIdentifier.resolve("com.example.hostile.a.ordinary", info: info), "com.example.hostile.a.ordinary")
    }

    func testMissingDeclarationOtherOwnerAndEmptyWildcardJobCannotBeMapped() {
        let info: [String: Any] = ["JibunKitOriginalBundleIdentifier": original,
            "CFBundleIdentifier": installed,
            "BGTaskSchedulerPermittedIdentifiers": [installed + ".b.ordinary", installed + ".b.export.*"]]
        for suffix in [".a.ordinary", ".a.export.job", ".b.export."] {
            XCTAssertEqual(MiniAppBackgroundTaskIdentifier.resolve(original + suffix, info: info), original + suffix)
        }
    }

    @MainActor
    func testLaunchFailureCannotBeBypassedByManagementEnableOrRestore() async throws {
        enum Rejected: Error { case registration }
        var aStarts = 0, bStarts = 0
        let a = MiniAppFeatureLifetime(id: MiniAppID("launch-a")) { _ in aStarts += 1 }
        let b = MiniAppFeatureLifetime(id: MiniAppID("launch-b")) { _ in bStarts += 1 }
        a.recordLaunchRegistrationFailure(Rejected.registration)
        a.setStartAllowed(false); a.setStartAllowed(true)
        try await a.restoreLifecycle.stop(); try await a.restoreLifecycle.resume()
        do { try await a.start(); XCTFail("Failed launch must remain closed") }
        catch MiniAppFeatureLifetime.Failure.launchRegistrationFailed(_) { }
        try await b.start()
        XCTAssertEqual(aStarts, 0); XCTAssertEqual(bStarts, 1)
        XCTAssertNil(a.runtime); XCTAssertEqual(b.state, .running)
        await b.stop()
    }
}
