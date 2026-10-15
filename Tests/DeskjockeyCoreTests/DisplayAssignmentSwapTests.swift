import XCTest
@testable import DeskjockeyCore

final class DisplayAssignmentSwapTests: XCTestCase {
    @MainActor func testSwapUsesDestinationModesAndPreservesTheClassAndOtherInstance() async throws {
        let manager = MockDisplayManager()
        manager.displays[2].mode = DisplayMode(logicalSize: .init(width: 1280, height: 720), pixelSize: .init(width: 2560, height: 1440))
        manager.displays[2].frame.size = manager.displays[2].mode.logicalSize
        let before = manager.displays
        let store = InMemoryDisplaySetStore()
        let engine = coordinator(manager, store)
        _ = await engine.processDisplayChange()
        let configuration = store.database.classes[0].configuration
        let swapped = await engine.swapDisplayAssignments(firstRuntimeID: "5", secondRuntimeID: "6")
        XCTAssertTrue(swapped)
        XCTAssertEqual(store.database.classes[0].configuration, configuration)
        XCTAssertEqual(manager.displays[0], before[0])
        XCTAssertEqual(manager.displays[1].mode, before[2].mode)
        XCTAssertEqual(manager.displays[2].mode, before[1].mode)
        XCTAssertFalse(manager.displays[1].isMain)
        XCTAssertTrue(manager.displays[2].isMain)
        XCTAssertEqual(manager.plans.count, 1)
        XCTAssertEqual(manager.plans[0].targets.count, 3)
        let correctedInstance = store.database.classes[0].instances[0]

        manager.displays = sampleDisplays(serials: (300, 400))
        _ = await engine.processDisplayChange()
        let otherInstance = try XCTUnwrap(store.database.classes[0].instances.first { $0.devices != correctedInstance.devices })
        manager.displays = before
        _ = await engine.processDisplayChange()
        XCTAssertEqual(manager.displays[1].frame, before[2].frame)
        XCTAssertTrue(manager.displays[2].isMain)
        XCTAssertTrue(store.database.classes[0].instances.contains(otherInstance))
        let undone = await engine.swapDisplayAssignments(firstRuntimeID: "5", secondRuntimeID: "6")
        XCTAssertTrue(undone)
        XCTAssertEqual(manager.displays, before)
        XCTAssertEqual(store.database.classes[0].configuration, configuration)
    }

    @MainActor func testSystemSettingsPermutationChangesOnlyTheInstanceEvenAfterCoordinateRebase() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let logger = RecordingLogger()
        let engine = coordinator(manager, store, logger: logger)
        _ = await engine.processDisplayChange()
        let saved = store.database.classes[0]
        let firstFrame = manager.displays[1].frame
        manager.displays[1].frame = manager.displays[2].frame
        manager.displays[2].frame = firstFrame
        manager.displays[1].isMain = false
        manager.displays[2].isMain = true
        for i in manager.displays.indices { manager.displays[i].frame.origin.x += 600 }
        let result = await engine.processDisplayChange()
        XCTAssertTrue(result)
        XCTAssertEqual(store.database.classes[0].configuration, saved.configuration)
        XCTAssertNotEqual(store.database.classes[0].instances[0].assignments, saved.instances[0].assignments)
        XCTAssertTrue(manager.plans.isEmpty)
        XCTAssertTrue(logger.contains("instance_permutation"))
        XCTAssertTrue(engine.state.matchesScreenConfiguration)
    }

    @MainActor func testMissingOrDuplicateSerialsDoNotDisableManualSwap() async throws {
        for serial: UInt32 in [0, 72] {
            let manager = MockDisplayManager(displays: sampleDisplays(serials: (serial, serial)))
            manager.displays[1].logicalUnitNumber = 0
            manager.displays[2].logicalUnitNumber = 0
            let store = InMemoryDisplaySetStore()
            let engine = coordinator(manager, store)
            _ = await engine.processDisplayChange()
            let before = manager.displays
            XCTAssertEqual(engine.state.swapCandidates.count, 1)
            let swapped = await engine.swapDisplayAssignments(firstRuntimeID: "5", secondRuntimeID: "6")
            XCTAssertTrue(swapped)
            XCTAssertTrue(store.database.classes[0].instances.isEmpty)
            XCTAssertEqual(manager.displays[1].frame, before[2].frame)
            _ = await engine.processDisplayChange()
            let undone = await engine.swapDisplayAssignments(firstRuntimeID: "5", secondRuntimeID: "6")
            XCTAssertTrue(undone)
            XCTAssertEqual(manager.displays, before)
        }
    }

    @MainActor func testInvalidOrDisconnectedPairDoesNotChangeSettingsOrClasses() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let engine = coordinator(manager, store)
        _ = await engine.processDisplayChange()
        let saved = store.database
        let before = manager.displays
        let mismatched = await engine.swapDisplayAssignments(firstRuntimeID: "1", secondRuntimeID: "5")
        let disconnected = await engine.swapDisplayAssignments(firstRuntimeID: "5", secondRuntimeID: "999")
        XCTAssertFalse(mismatched)
        XCTAssertFalse(disconnected)
        XCTAssertEqual(manager.displays, before)
        XCTAssertEqual(store.database, saved)
        XCTAssertTrue(manager.plans.isEmpty)
    }

    @MainActor func testSwapFailureDoesNotPersistANewInstanceAssignment() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let engine = coordinator(manager, store)
        _ = await engine.processDisplayChange()
        let saved = store.database
        manager.failApply = true
        let success = await engine.swapDisplayAssignments(firstRuntimeID: "5", secondRuntimeID: "6")
        XCTAssertFalse(success)
        XCTAssertEqual(store.database, saved)
    }
}
