import XCTest
import JibunKitCore

final class MiniAppSceneActivityTests: XCTestCase {
    private let a = MiniAppID("scene-a")
    private let b = MiniAppID("scene-b")

    @MainActor
    func testUncreatedAndSelectedFeaturesReceiveScenePhaseSeparately() {
        var first: [MiniAppSceneActivity] = []
        var second: [MiniAppSceneActivity] = []
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: a) { first.append($0) }, .init(id: b) { second.append($0) },
        ])
        dispatcher.connect(phase: .active, selectedID: a)
        dispatcher.update(phase: .active, selectedID: b)
        dispatcher.update(phase: .background, selectedID: b)
        dispatcher.update(phase: .active, selectedID: b)
        dispatcher.update(phase: .active, selectedID: nil)
        XCTAssertEqual(first.map(\.isSelected), [true, false, false, false])
        XCTAssertEqual(second.map(\.isSelected), [false, true, true, true, false])
        XCTAssertEqual(second.map(\.phase), [.active, .active, .background, .active, .active])
        XCTAssertTrue(first.allSatisfy { $0.featureID == a && $0.isConnected })
        XCTAssertEqual(Set((first + second).map(\.sceneID)).count, 1)
    }

    @MainActor
    func testClosingOneSceneDoesNotEndAnotherAndReconnectHasNewIdentity() {
        var first: [MiniAppSceneActivity] = []
        var second: [MiniAppSceneActivity] = []
        let one = MiniAppSceneActivityDispatcher(handlers: [.init(id: a) { first.append($0) }])
        let two = MiniAppSceneActivityDispatcher(handlers: [.init(id: a) { second.append($0) }])
        one.update(phase: .active, selectedID: a)
        XCTAssertTrue(first.isEmpty)
        one.connect(phase: .active, selectedID: a)
        two.connect(phase: .active, selectedID: a)
        let originalID = first.last?.sceneID
        XCTAssertEqual(one.connectionID, originalID)
        XCTAssertEqual(two.connectionID, second.last?.sceneID)
        XCTAssertNotEqual(originalID, second.last?.sceneID)
        one.disconnect()
        XCTAssertNil(one.connectionID)
        one.disconnect()
        one.update(phase: .background, selectedID: a)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.last?.isConnected, false)
        XCTAssertEqual(first.last?.isSelected, false)
        XCTAssertEqual(first.last?.sceneID, originalID)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.last?.isConnected, true)
        one.connect(phase: .inactive, selectedID: nil)
        XCTAssertNotEqual(first.last?.sceneID, originalID)
        XCTAssertEqual(one.connectionID, first.last?.sceneID)
    }

    @MainActor
    func testReentrantDisconnectReconnectCompletesEachTransitionForEveryOwner() {
        var first: [MiniAppSceneActivity] = []
        var second: [MiniAppSceneActivity] = []
        var dispatcher: MiniAppSceneActivityDispatcher?
        dispatcher = MiniAppSceneActivityDispatcher(handlers: [
            .init(id: a) { activity in
                first.append(activity)
                if first.count == 1 {
                    dispatcher?.disconnect()
                    dispatcher?.connect(phase: .background, selectedID: self.b)
                }
            },
            .init(id: b) { second.append($0) },
        ])
        dispatcher?.connect(phase: .active, selectedID: a)
        XCTAssertEqual(first.map(\.phase), [.active, nil, .background])
        XCTAssertEqual(second.map(\.phase), first.map(\.phase))
        XCTAssertEqual(second.map(\.sceneID), first.map(\.sceneID))
        XCTAssertEqual(second.map(\.isSelected), [false, false, true])
        XCTAssertNotEqual(first.first?.sceneID, first.last?.sceneID)
        dispatcher = nil
    }

    @MainActor
    func testDuplicateUpdatesDoNotDeliverAndSelectionDoesNotCancelFeatureWork() async throws {
        var events: [MiniAppSceneActivity] = []
        var cleanedUp = false
        let runtime = MiniAppRuntime()
        try runtime.onShutdown { cleanedUp = true }
        let dispatcher = MiniAppSceneActivityDispatcher(handlers: [.init(id: a) { events.append($0) }])
        dispatcher.connect(phase: .active, selectedID: a)
        dispatcher.connect(phase: .active, selectedID: a)
        dispatcher.update(phase: .active, selectedID: a)
        XCTAssertEqual(events.count, 1)
        dispatcher.update(phase: .active, selectedID: b)
        dispatcher.disconnect()
        XCTAssertFalse(cleanedUp)
        XCTAssertFalse(runtime.isClosed)
        await runtime.shutdown()
        XCTAssertTrue(cleanedUp)
    }
}
