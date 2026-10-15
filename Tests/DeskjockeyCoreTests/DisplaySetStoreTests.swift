import XCTest
@testable import DeskjockeyCore

final class DisplaySetStoreTests: XCTestCase {
    private func withFile(_ operation: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory.appendingPathComponent("profiles.json"))
    }

    private func displaySetClass() throws -> DisplaySetClass {
        let displays = sampleDisplays()
        return DisplaySetClass(configuration: try ScreenConfigurationLogic.capture(displays, mapping: SlotAssignmentResolver.initialSlotAssignments(displays)))
    }

    private func legacyData(names: [String]) throws -> Data {
        let slots: [[String: Any]] = names.enumerated().map { i, name in
            ["modelName": name, "slotIndex": 0,
             "targetFrame": ["origin": ["x": i * 1920, "y": 0], "size": ["width": 1920, "height": 1080]],
             "targetResolution": ["width": 1920, "height": 1080]]
        }
        return try JSONSerialization.data(withJSONObject: [["signatureRawValue": "legacy", "slots": slots, "updatedAt": 1]])
    }

    func testVersionedRoundTripPreservesConfigurationAndInstances() throws {
        try withFile { url in
            let store = JSONDisplaySetStore(fileURL: url)
            var saved = try displaySetClass()
            let displays = sampleDisplays()
            saved.record(try XCTUnwrap(ScreenConfigurationLogic.instance(displays, mapping: SlotAssignmentResolver.initialSlotAssignments(displays), now: Date())))
            let database = DisplaySetDatabase(classes: [saved])
            try store.saveDatabase(database)
            XCTAssertEqual(try store.loadDatabase(), database)
        }
    }

    func testVersionTwoWireFormatSurvivesDomainRenames() throws {
        // Fixed pre-rename data protects the compatibility boundary independently of the current encoder.
        let original = Data(#"{"schemaVersion":2,"profiles":[{"configuration":{"slots":[{"id":7,"modelID":{"vendorID":1,"productID":2},"label":"Panel (1)","isBuiltIn":false,"targetFrame":{"origin":{"x":0,"y":0},"size":{"width":100,"height":100}},"targetMode":{"logicalSize":{"width":100,"height":100},"pixelSize":{"width":200,"height":200}}}],"mainSlotID":7},"instances":[{"assignments":[{"deviceID":{"modelID":{"vendorID":1,"productID":2},"serialNumber":42},"slotID":7,"logicalUnitNumber":3}],"lastUsedAt":2}],"updatedAt":1,"lastUsedAt":2}],"legacyProfiles":[]}"#.utf8)
        // The slot label is removed; an old file that still has the key decodes, and the key is dropped on save.
        let withoutLabel = Data(#"{"schemaVersion":2,"profiles":[{"configuration":{"slots":[{"id":7,"modelID":{"vendorID":1,"productID":2},"isBuiltIn":false,"targetFrame":{"origin":{"x":0,"y":0},"size":{"width":100,"height":100}},"targetMode":{"logicalSize":{"width":100,"height":100},"pixelSize":{"width":200,"height":200}}}],"mainSlotID":7},"instances":[{"assignments":[{"deviceID":{"modelID":{"vendorID":1,"productID":2},"serialNumber":42},"slotID":7,"logicalUnitNumber":3}],"lastUsedAt":2}],"updatedAt":1,"lastUsedAt":2}],"legacyProfiles":[]}"#.utf8)
        try withFile { url in
            try original.write(to: url)
            let store = JSONDisplaySetStore(fileURL: url)
            let database = try store.loadDatabase()
            let displaySetClass = try XCTUnwrap(database.classes.first)
            XCTAssertEqual(displaySetClass.configuration.mainSlotID, 7)
            XCTAssertEqual(displaySetClass.instances.first?.assignments.first?.deviceID.serialNumber, 42)
            try store.saveDatabase(database)
            let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
            let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: withoutLabel) as? NSDictionary)
            XCTAssertEqual(saved, expected)
            XCTAssertNil(saved["classes"])
            XCTAssertNotNil(saved["profiles"])
            XCTAssertEqual(database.schemaVersion, 2)
        }
    }

    func testCorruptAndFutureFilesAreNeverReplaced() throws {
        try withFile { url in
            for data in [Data("invalid json".utf8), Data(#"{"schemaVersion":99,"profiles":[],"legacyProfiles":[]}"#.utf8)] {
                try data.write(to: url)
                let store = JSONDisplaySetStore(fileURL: url)
                XCTAssertThrowsError(try store.loadDatabase())
                XCTAssertThrowsError(try store.saveDatabase(DisplaySetDatabase()))
                XCTAssertEqual(try Data(contentsOf: url), data)
            }
        }
    }

    func testConcurrentExternalEditIsNotOverwritten() throws {
        try withFile { url in
            let store = JSONDisplaySetStore(fileURL: url)
            try store.saveDatabase(DisplaySetDatabase())
            let baseline = try store.loadDatabase()
            let external = try JSONEncoder().encode(DisplaySetDatabase(classes: [displaySetClass()]))
            try external.write(to: url)
            XCTAssertThrowsError(try store.saveDatabase(baseline))
            XCTAssertEqual(try Data(contentsOf: url), external)
        }
    }

    func testLegacyLoadIsReadOnlyAndConversionCreatesExactBackup() throws {
        try withFile { url in
            let original = try legacyData(names: ["Example (1)", "Example (2)"])
            try original.write(to: url)
            let store = JSONDisplaySetStore(fileURL: url)
            var database = try store.loadDatabase()
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertEqual(database.legacyProfiles.count, 1)
            XCTAssertTrue(database.classes.isEmpty)
            database.classes = [try displaySetClass()]
            try store.saveDatabase(database)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("v1-backup")), original)
            XCTAssertEqual(try store.loadDatabase(), database)
            try store.saveDatabase(database)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("v1-backup")), original)
        }
    }

    @MainActor func testLegacyNumberedSlotsKeepTheirAssociationWithoutSerialHistory() async throws {
        let legacy = try JSONDecoder().decode([LegacyProfile].self, from: legacyData(names: ["Example (1)", "Example (2)"]))
        var displays = Array(sampleDisplays(serials: (200, 100)).suffix(2))
        displays[0].displayName = "Example (1)"; displays[1].displayName = "Example (2)"
        let manager = MockDisplayManager(displays: displays)
        let store = InMemoryDisplaySetStore()
        store.database.legacyProfiles = legacy
        let engine = coordinator(manager, store)
        let result = await engine.processDisplayChange()
        XCTAssertTrue(result)
        XCTAssertEqual(manager.displays, displays)
        XCTAssertTrue(manager.plans.isEmpty)
        XCTAssertEqual(store.database.legacyProfiles, legacy)
        let instance = try XCTUnwrap(store.database.classes.first?.instances.first)
        XCTAssertEqual(instance.assignments.first { $0.deviceID.serialNumber == 200 }?.slotID, 0)
        XCTAssertEqual(instance.assignments.first { $0.deviceID.serialNumber == 100 }?.slotID, 1)
    }

    @MainActor func testAmbiguousLegacyLayoutsRemainIntact() async throws {
        let legacy = try JSONDecoder().decode([LegacyProfile].self, from: legacyData(names: ["LEN T23i-20 (1)", "LEN T23i-20 (2)"]))
        let manager = MockDisplayManager(displays: Array(sampleDisplays().suffix(2)))
        let store = InMemoryDisplaySetStore()
        store.database.legacyProfiles = legacy + legacy
        let logger = RecordingLogger()
        let success = await coordinator(manager, store, logger: logger).processDisplayChange()
        XCTAssertTrue(success)
        XCTAssertEqual(store.database.legacyProfiles, legacy + legacy)
        XCTAssertEqual(store.database.classes.count, 1)
        XCTAssertTrue(manager.plans.isEmpty)
        XCTAssertTrue(logger.contains("legacy_conflict"))
    }

    func testInvalidInstanceKeysAndDuplicateClassesAreRejected() throws {
        var saved = try displaySetClass()
        let displays = sampleDisplays()
        let instance = try XCTUnwrap(ScreenConfigurationLogic.instance(displays, mapping: SlotAssignmentResolver.initialSlotAssignments(displays), now: Date()))
        saved.instances = [instance, instance]
        XCTAssertThrowsError(try JSONDisplaySetStore.validate(DisplaySetDatabase(classes: [saved])))
        saved.instances = []
        XCTAssertThrowsError(try JSONDisplaySetStore.validate(DisplaySetDatabase(classes: [saved, saved])))
    }
}
