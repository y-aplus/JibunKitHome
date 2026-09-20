#if os(iOS)
import Foundation
import XCTest
import JibunKitCore

@MainActor
final class P2ActionNativeTests: XCTestCase {
    func testActionEntrySelectsActionSpecificCopyAndContract() {
        let controller = ActionViewController()
        XCTAssertEqual(controller.incomingPresentation, .action)
        XCTAssertEqual(controller.incomingPresentation.accessibilityPrefix, "action")
        XCTAssertTrue(controller.incomingPresentation.explanation.contains("出力項目は返しません"))
        XCTAssertNotEqual(controller.incomingPresentation, .share)
    }

    func testTwoOwnerAdmissionAndDurableReceiptRemainOwned() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try MiniAppIncomingStore(containerURL: root)
        try inbox.publish([P2ActionProbe.alpha, P2ActionProbe.beta])

        let alphaReceipt = try inbox.enqueue(for: MiniAppID(P2ActionProbe.alpha.id), inputs: [.text("alpha")])
        let betaReceipt = try inbox.enqueue(for: MiniAppID(P2ActionProbe.beta.id), inputs: [.url(URL(string: "https://example.invalid/beta")!)])
        XCTAssertEqual(alphaReceipt.owner, P2ActionProbe.alpha.id)
        XCTAssertEqual(betaReceipt.owner, P2ActionProbe.beta.id)

        try inbox.setAdmission(P2ActionProbe.alpha, enabled: false)
        XCTAssertThrowsError(try inbox.enqueue(for: MiniAppID(P2ActionProbe.alpha.id), inputs: [.text("closed")])) {
            XCTAssertEqual($0 as? MiniAppIncomingError, .unavailableOwner(P2ActionProbe.alpha.id))
        }
        XCTAssertEqual(try inbox.pending(for: MiniAppID(P2ActionProbe.alpha.id)).receipts.map(\.id), [alphaReceipt.id])
        XCTAssertEqual(try inbox.pending(for: MiniAppID(P2ActionProbe.beta.id)).receipts.map(\.id), [betaReceipt.id])
    }

    func testPendingReceiptsSurviveHostWithoutRegisteredOwnersAndDeliverAfterRepublish() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alpha = MiniAppID(P2ActionProbe.alpha.id)
        let beta = MiniAppID(P2ActionProbe.beta.id)

        let actionProcessStore = try MiniAppIncomingStore(containerURL: root)
        try actionProcessStore.publish([P2ActionProbe.alpha, P2ActionProbe.beta])
        let alphaReceipt = try actionProcessStore.enqueue(for: alpha, inputs: [.text("pending action text")])
        let betaReceipt = try actionProcessStore.enqueue(
            for: beta, inputs: [.url(try XCTUnwrap(URL(string: "https://example.invalid/retained-beta")))]
        )

        // Model an overwritten host that uses the same App Group but does not
        // register the optional Action destinations. A fresh store instance is
        // required so this exercises the durable filesystem, not retained state.
        let hostWithoutAction = try MiniAppIncomingStore(containerURL: root)
        try hostWithoutAction.publish([])
        XCTAssertTrue(try hostWithoutAction.destinations().isEmpty)
        XCTAssertThrowsError(try hostWithoutAction.enqueue(for: alpha, inputs: [.text("must reject")])) {
            XCTAssertEqual($0 as? MiniAppIncomingError, .unavailableOwner(alpha.rawValue))
        }
        XCTAssertEqual(Set(try hostWithoutAction.ownersWithReceipts()), Set([alpha, beta]))
        XCTAssertEqual(try hostWithoutAction.pending(for: alpha).receipts.map(\.id), [alphaReceipt.id])
        XCTAssertEqual(try hostWithoutAction.pending(for: beta).receipts.map(\.id), [betaReceipt.id])

        // Model reinstalling/re-enabling the diagnostic registrations. Reopen
        // the store again, republish new admission generations, and consume via
        // the real delivery path before acknowledging the receipt.
        let republishedHost = try MiniAppIncomingStore(containerURL: root)
        try republishedHost.publish([P2ActionProbe.alpha, P2ActionProbe.beta])
        var deliveredText: String?
        let provider = MiniAppIncomingProvider(id: alpha, typeIdentifiers: ["public.text"]) { receipt, _ in
            deliveredText = receipt.items.count == 1 ? receipt.items[0].value : nil
        }
        try await MiniAppIncomingDelivery().deliver(
            id: alphaReceipt.id, provider: provider, lifetime: nil, inbox: republishedHost
        )

        XCTAssertEqual(deliveredText, "pending action text")
        XCTAssertTrue(try republishedHost.pending(for: alpha).receipts.isEmpty)
        XCTAssertEqual(try republishedHost.pending(for: beta).receipts.map(\.id), [betaReceipt.id])
    }
}
#endif
