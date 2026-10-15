import XCTest
@testable import DeskjockeyCore

final class ScreenConfigurationLifecycleTests: XCTestCase {
    @MainActor func testConnectionEventClearsSessionAssignmentsEvenWithReusedRuntimeIDs() async throws {
        let manager = MockDisplayManager(displays: sampleDisplays(serials: (0, 0)))
        manager.displays[1].logicalUnitNumber = 0
        manager.displays[2].logicalUnitNumber = 0
        let original = manager.displays
        let store = InMemoryDisplaySetStore()
        let engine = coordinator(manager, store)
        _ = await engine.processDisplayChange()
        _ = await engine.swapDisplayAssignments(firstRuntimeID: "5", secondRuntimeID: "6")
        XCTAssertNotEqual(manager.displays, original)
        engine.displayConnectionDidChange()
        let restored = await engine.processDisplayChange()
        XCTAssertTrue(restored)
        XCTAssertEqual(manager.displays, original)
        XCTAssertTrue(store.database.classes[0].instances.isEmpty)
    }

    @MainActor func testTopologyChangeDuringApplyIsReprocessedWithoutPersistingStaleInstance() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let sleeper = GateSleepManager()
        let logger = RecordingLogger()
        let engine = ScreenConfigurationCoordinator(displayManager: manager, displaySetStore: store,
                                                     logger: logger, sleepManager: sleeper, reapplyDelayMilliseconds: 0)
        _ = await engine.processDisplayChange()
        manager.displays = sampleDisplays(serials: (300, 400))
        manager.displays[2].frame.origin.y = 500
        sleeper.pauseAt = sleeper.calls + 2
        let task = Task { await engine.processDisplayChange() }
        for _ in 0..<1000 {
            if sleeper.paused { break }
            await Task.yield()
        }
        XCTAssertTrue(sleeper.paused)
        manager.displays = sampleDisplays(serials: (500, 600))
        manager.displays[2].frame.origin.y = 200
        engine.displayConnectionDidChange()
        let queued = await engine.processDisplayChange()
        XCTAssertFalse(queued)
        sleeper.resume()
        let completed = await task.value
        XCTAssertTrue(completed)
        let serials = store.database.classes[0].instances.flatMap { $0.devices.map(\.serialNumber) }
        XCTAssertFalse(serials.contains(300))
        XCTAssertFalse(serials.contains(400))
        XCTAssertTrue(serials.contains(500))
        XCTAssertTrue(serials.contains(600))
        XCTAssertTrue(engine.state.matchesScreenConfiguration)
        XCTAssertTrue(logger.contains("apply_result_mismatch"))
    }
}

@MainActor
private final class GateSleepManager: SleepManaging {
    var calls = 0
    var pauseAt: Int?
    var paused = false
    private var continuation: CheckedContinuation<Void, Never>?
    func sleep(milliseconds: UInt64) async {
        calls += 1
        guard calls == pauseAt else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            paused = true
        }
    }
    func resume() {
        continuation?.resume()
        continuation = nil
        paused = false
    }
}
