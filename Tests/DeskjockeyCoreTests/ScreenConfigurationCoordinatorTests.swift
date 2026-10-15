import XCTest
@testable import DeskjockeyCore

final class ScreenConfigurationCoordinatorTests: XCTestCase {
    @MainActor func testUnknownClassIsCapturedAtLaunchAndAfterConnection() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let engine = coordinator(manager, store)
        let first = await engine.processDisplayChange()
        XCTAssertTrue(first)
        XCTAssertEqual(store.database.classes.count, 1)
        XCTAssertEqual(store.database.classes[0].instances.count, 1)
        XCTAssertTrue(engine.state.matchesScreenConfiguration)
        XCTAssertTrue(manager.plans.isEmpty)
        manager.displays[2].modelID = DisplayModelID(vendorID: 9, productID: 9)
        let second = await engine.processDisplayChange()
        XCTAssertTrue(second)
        XCTAssertEqual(store.database.classes.count, 2)
    }

    @MainActor func testNewInstanceAlwaysReceivesTheKnownClassConfiguration() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let logger = RecordingLogger()
        let engine = coordinator(manager, store, logger: logger)
        _ = await engine.processDisplayChange()
        let original = store.database.classes[0].configuration
        manager.displays = sampleDisplays(serials: (300, 400))
        manager.displays[1].runtimeID = "15"
        manager.displays[2].runtimeID = "16"
        manager.displays[2].mode.pixelSize = DisplaySize(width: 1280, height: 720)
        manager.displays[2].frame.origin.x = 4000
        let success = await engine.processDisplayChange()
        XCTAssertTrue(success)
        XCTAssertEqual(manager.plans.count, 1)
        XCTAssertEqual(manager.plans[0].targets.count, 3)
        XCTAssertEqual(store.database.classes[0].configuration, original)
        XCTAssertEqual(store.database.classes[0].instances.count, 2)
        XCTAssertTrue(engine.state.matchesScreenConfiguration)
        XCTAssertTrue(logger.contains("logical_unit_hint"))
        XCTAssertTrue(logger.contains("configuration_applied"))
    }

    @MainActor func testSettingsEditUpdatesTheClassForAllInstances() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let engine = coordinator(manager, store)
        _ = await engine.processDisplayChange()
        let oldIDs = store.database.classes[0].configuration.slots.map(\.id)
        manager.displays[2].frame.origin.y = 120
        manager.displays[2].mode.pixelSize = DisplaySize(width: 3840, height: 2160)
        let edit = await engine.processDisplayChange()
        XCTAssertTrue(edit)
        XCTAssertTrue(manager.plans.isEmpty)
        let edited = store.database.classes[0].configuration
        XCTAssertEqual(edited.slots.map(\.id), oldIDs)
        manager.displays = sampleDisplays(serials: (300, 400))
        _ = await engine.processDisplayChange()
        XCTAssertEqual(manager.displays[2].frame.origin.y, 120)
        XCTAssertEqual(manager.displays[2].mode.pixelSize.width, 3840)
        manager.displays = sampleDisplays()
        _ = await engine.processDisplayChange()
        XCTAssertEqual(manager.displays[2].frame.origin.y, 120)
        XCTAssertEqual(store.database.classes[0].configuration, edited)
        XCTAssertEqual(store.database.classes[0].instances.count, 2)
    }

    @MainActor func testInputAndStorageFailuresDoNotOverwriteSavedData() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let logger = RecordingLogger()
        let engine = coordinator(manager, store, logger: logger)
        _ = await engine.processDisplayChange()
        let original = store.database
        let saves = store.saves
        store.failLoad = true
        manager.displays[2].frame.origin.y = 50
        let failedRead = await engine.processDisplayChange()
        XCTAssertFalse(failedRead)
        XCTAssertEqual(store.database, original)
        XCTAssertEqual(store.saves, saves)
        store.failLoad = false
        manager.displays[1].modelID = nil
        manager.displays[1].identityIssue = "raw_vendor_id=0 raw_product_id=0"
        let invalid = await engine.processDisplayChange()
        XCTAssertFalse(invalid)
        XCTAssertEqual(store.database, original)
        XCTAssertTrue(manager.plans.isEmpty)
        XCTAssertTrue(logger.contains("raw_vendor_id=0"))
        XCTAssertTrue(logger.contains("operation_failed"))
        XCTAssertTrue(logger.contains("test_read_failure"))
    }

    @MainActor func testFailedAndAdjustedApplyDoNotBecomeClassEdits() async throws {
        for fail in [true, false] {
            let manager = MockDisplayManager()
            let store = InMemoryDisplaySetStore()
            let logger = RecordingLogger()
            let engine = coordinator(manager, store, logger: logger)
            _ = await engine.processDisplayChange()
            let original = store.database
            manager.displays = sampleDisplays(serials: (300, 400))
            manager.displays[2].frame.origin.y = 400
            manager.failApply = fail
            if !fail { manager.afterApply = { manager.displays[2].frame.origin.y = 20 } }
            let applied = await engine.processDisplayChange()
            XCTAssertFalse(applied)
            XCTAssertEqual(store.database, original)
            _ = await engine.processDisplayChange()
            XCTAssertEqual(store.database, original, "A callback for our failed apply must not rewrite the class")
            XCTAssertTrue(logger.contains(fail ? "test_apply_failure" : "apply_result_mismatch"))
        }
    }

    @MainActor func testFailedSaveDoesNotClaimPersistence() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let logger = RecordingLogger()
        let engine = coordinator(manager, store, logger: logger)
        _ = await engine.processDisplayChange()
        let original = store.database
        store.failSave = true
        manager.displays[2].frame.origin.y = 60
        let success = await engine.processDisplayChange()
        XCTAssertFalse(success)
        XCTAssertEqual(store.database, original)
        XCTAssertTrue(logger.contains("display_set_database_save_failed"))
    }

    @MainActor func testInstanceSavedDiagnosticOccursOnlyAfterSuccessfulStorage() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let logger = RecordingLogger()
        let engine = coordinator(manager, store, logger: logger)
        _ = await engine.processDisplayChange()
        let records = try logger.lines.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String])
        }
        let databaseSaved = try XCTUnwrap(records.firstIndex { $0["reason"] == "display_set_database_saved" })
        let instanceSaved = try XCTUnwrap(records.firstIndex { $0["reason"] == "instance_saved" })
        XCTAssertGreaterThan(instanceSaved, databaseSaved)

        logger.lines.removeAll()
        store.failSave = true
        let success = await engine.captureCurrentScreenConfiguration()
        XCTAssertFalse(success)
        XCTAssertTrue(logger.contains("instance_identified"))
        XCTAssertTrue(logger.contains("display_set_database_save_failed"))
        XCTAssertFalse(logger.contains("instance_saved"))
    }

    @MainActor func testUnknownSerialsAllowRestoreWithoutPersistentInstance() async throws {
        let manager = MockDisplayManager()
        let store = InMemoryDisplaySetStore()
        let logger = RecordingLogger()
        let engine = coordinator(manager, store, logger: logger)
        _ = await engine.processDisplayChange()
        manager.displays = sampleDisplays(serials: (0, 0))
        manager.displays[2].frame.origin.y = 300
        let success = await engine.processDisplayChange()
        XCTAssertTrue(success)
        XCTAssertEqual(store.database.classes[0].instances.count, 1)
        XCTAssertTrue(engine.state.matchesScreenConfiguration)
        XCTAssertTrue(logger.contains("session_only_identity"))
        XCTAssertTrue(logger.contains("missing_serial"))
    }

    @MainActor func testLogRecordsHaveDetectionIDsAndEscapeExternalLabels() async throws {
        let manager = MockDisplayManager()
        manager.displays[1].displayName = "screen\nreason=fake_failure"
        let store = InMemoryDisplaySetStore()
        let logger = RecordingLogger()
        _ = await coordinator(manager, store, logger: logger).processDisplayChange()
        let records = try logger.lines.map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String]) }
        XCTAssertEqual(Set(records.compactMap { $0["detection_id"] }).count, 1)
        XCTAssertTrue(records.contains { $0["display_name"] == manager.displays[1].displayName && $0["model_id"] == externalModel.description })
        XCTAssertTrue(records.allSatisfy { $0["reason"] != nil })
        XCTAssertTrue(logger.lines.allSatisfy { !$0.contains("\n") })
    }
}
