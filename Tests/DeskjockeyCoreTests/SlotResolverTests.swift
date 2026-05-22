import XCTest
@testable import DeskjockeyCore

final class SlotResolverTests: XCTestCase {

    // MARK: - Trivial cases

    func testSingleDisplayAlwaysGetsSlotZero() {
        let display = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            serialNumber: 42,
            portIdentifier: 3,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let (pairs, assignment) = SlotResolver.resolve(displays: [display], knownAssignments: [])
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].slotIndex, 0)
        XCTAssertEqual(assignment.entries.count, 1)
        XCTAssertEqual(assignment.entries[0].serialNumber, 42)
    }

    func testDifferentModelsEachGetSlotZero() {
        let dell = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let macbook = DisplaySnapshot(
            runtimeID: "D2",
            modelName: "MacBook Pro Display",
            isBuiltIn: true,
            frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1728, height: 1117)),
            resolution: .init(width: 1728, height: 1117)
        )
        let (pairs, _) = SlotResolver.resolve(displays: [dell, macbook], knownAssignments: [])
        let byModel = Dictionary(uniqueKeysWithValues: pairs.map { ($0.display.normalizedModelName, $0.slotIndex) })
        XCTAssertEqual(byModel["Dell U2405"], 0)
        XCTAssertEqual(byModel["MacBook Pro Display"], 0)
    }

    // MARK: - Step 1: Serial match

    func testSerialMatchAssignsKnownSlots() {
        let displayA = DisplaySnapshot(
            runtimeID: "A",
            modelName: "Dell U2405",
            serialNumber: 100,
            portIdentifier: 5,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let displayB = DisplaySnapshot(
            runtimeID: "B",
            modelName: "Dell U2405",
            serialNumber: 200,
            portIdentifier: 7,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )

        // Known: serial 200 was slot 0, serial 100 was slot 1
        let known = SlotAssignment(entries: [
            SlotAssignmentEntry(modelName: "Dell U2405", slotIndex: 0, serialNumber: 200, portIdentifier: 7),
            SlotAssignmentEntry(modelName: "Dell U2405", slotIndex: 1, serialNumber: 100, portIdentifier: 5),
        ], lastUsedAt: Date())

        let (pairs, _) = SlotResolver.resolve(displays: [displayA, displayB], knownAssignments: [known])
        let bySerial = Dictionary(uniqueKeysWithValues: pairs.map { ($0.display.serialNumber, $0.slotIndex) })
        XCTAssertEqual(bySerial[100], 1, "Serial 100 should get slot 1 from known assignment")
        XCTAssertEqual(bySerial[200], 0, "Serial 200 should get slot 0 from known assignment")
    }

    // MARK: - Step 2: Elimination

    func testEliminationAssignsLastRemainingSlot() {
        let displayA = DisplaySnapshot(
            runtimeID: "A",
            modelName: "Dell U2405",
            serialNumber: 100,
            portIdentifier: 5,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let displayB = DisplaySnapshot(
            runtimeID: "B",
            modelName: "Dell U2405",
            serialNumber: 999,  // Unknown serial
            portIdentifier: 99, // Unknown port
            isBuiltIn: false,
            frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )

        // Only serial 100 is known (slot 0). Serial 999 is unknown.
        let known = SlotAssignment(entries: [
            SlotAssignmentEntry(modelName: "Dell U2405", slotIndex: 0, serialNumber: 100, portIdentifier: 5),
            SlotAssignmentEntry(modelName: "Dell U2405", slotIndex: 1, serialNumber: 200, portIdentifier: 7),
        ], lastUsedAt: Date())

        let (pairs, _) = SlotResolver.resolve(displays: [displayA, displayB], knownAssignments: [known])
        let bySerial = Dictionary(uniqueKeysWithValues: pairs.map { ($0.display.serialNumber, $0.slotIndex) })
        XCTAssertEqual(bySerial[100], 0, "Known serial gets its slot")
        XCTAssertEqual(bySerial[999], 1, "Unknown serial gets remaining slot by elimination")
    }

    // MARK: - Step 3: Port match

    func testPortMatchFallsThrough() {
        let displayA = DisplaySnapshot(
            runtimeID: "A",
            modelName: "Dell U2405",
            serialNumber: 300,  // New serial, not in known assignments
            portIdentifier: 5,  // But same port as known slot 0
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let displayB = DisplaySnapshot(
            runtimeID: "B",
            modelName: "Dell U2405",
            serialNumber: 400,  // New serial
            portIdentifier: 7,  // Same port as known slot 1
            isBuiltIn: false,
            frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )

        // Known: port 5 was slot 0, port 7 was slot 1 (different serials)
        let known = SlotAssignment(entries: [
            SlotAssignmentEntry(modelName: "Dell U2405", slotIndex: 0, serialNumber: 100, portIdentifier: 5),
            SlotAssignmentEntry(modelName: "Dell U2405", slotIndex: 1, serialNumber: 200, portIdentifier: 7),
        ], lastUsedAt: Date())

        let (pairs, _) = SlotResolver.resolve(displays: [displayA, displayB], knownAssignments: [known])
        let bySerial = Dictionary(uniqueKeysWithValues: pairs.map { ($0.display.serialNumber, $0.slotIndex) })
        XCTAssertEqual(bySerial[300], 0, "Port 5 → slot 0 via port match")
        XCTAssertEqual(bySerial[400], 1, "Port 7 → slot 1 via port match")
    }

    // MARK: - Step 4: Alphabetical fallback

    func testAlphabeticalFallbackWithNoKnownAssignments() {
        let displayA = DisplaySnapshot(
            runtimeID: "A",
            modelName: "Dell U2405",
            serialNumber: 500,
            portIdentifier: 10,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let displayB = DisplaySnapshot(
            runtimeID: "B",
            modelName: "Dell U2405",
            serialNumber: 300,
            portIdentifier: 20,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )

        let (pairs, _) = SlotResolver.resolve(displays: [displayA, displayB], knownAssignments: [])
        let bySerial = Dictionary(uniqueKeysWithValues: pairs.map { ($0.display.serialNumber, $0.slotIndex) })
        // Serial 300 < 500, so serial 300 gets slot 0
        XCTAssertEqual(bySerial[300], 0, "Lower serial gets slot 0")
        XCTAssertEqual(bySerial[500], 1, "Higher serial gets slot 1")
    }

    func testAlphabeticalFallbackZeroSerialsUsesPort() {
        let displayA = DisplaySnapshot(
            runtimeID: "A",
            modelName: "Dell U2405",
            serialNumber: 0,
            portIdentifier: 10,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let displayB = DisplaySnapshot(
            runtimeID: "B",
            modelName: "Dell U2405",
            serialNumber: 0,
            portIdentifier: 3,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )

        let (pairs, _) = SlotResolver.resolve(displays: [displayA, displayB], knownAssignments: [])
        let byPort = Dictionary(uniqueKeysWithValues: pairs.map { ($0.display.portIdentifier, $0.slotIndex) })
        // Port 3 < 10, so port 3 gets slot 0
        XCTAssertEqual(byPort[3], 0, "Lower port gets slot 0 when serials are zero")
        XCTAssertEqual(byPort[10], 1, "Higher port gets slot 1 when serials are zero")
    }

    // MARK: - SlotResolver.pair()

    func testPairMatchesSlotsToLiveDisplays() {
        let display = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            serialNumber: 42,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let slot = MonitorSlotProfile(
            modelName: "Dell U2405",
            slotIndex: 0,
            targetFrame: .init(origin: .init(x: 100, y: 200), size: .init(width: 1920, height: 1200)),
            targetResolution: .init(width: 1920, height: 1200)
        )

        let (pairs, _) = SlotResolver.pair(
            liveDisplays: [display],
            profileSlots: [slot],
            knownAssignments: []
        )
        XCTAssertEqual(pairs.count, 1)
        XCTAssertEqual(pairs[0].display.runtimeID, "D1")
        XCTAssertEqual(pairs[0].slot.targetFrame.origin.x, 100)
    }

    // MARK: - Assignment recording

    func testAssignmentUpsertBySerialSet() {
        var assignments: [SlotAssignment] = []

        let first = SlotAssignment(entries: [
            SlotAssignmentEntry(modelName: "Dell", slotIndex: 0, serialNumber: 100, portIdentifier: 5),
        ], lastUsedAt: Date(timeIntervalSince1970: 1000))

        assignments.upsert(first)
        XCTAssertEqual(assignments.count, 1)

        // Same serial set, different timestamp → replaces
        let updated = SlotAssignment(entries: [
            SlotAssignmentEntry(modelName: "Dell", slotIndex: 0, serialNumber: 100, portIdentifier: 7),
        ], lastUsedAt: Date(timeIntervalSince1970: 2000))
        assignments.upsert(updated)
        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(assignments[0].entries[0].portIdentifier, 7)

        // Different serial set → appends
        let different = SlotAssignment(entries: [
            SlotAssignmentEntry(modelName: "Dell", slotIndex: 0, serialNumber: 200, portIdentifier: 3),
        ], lastUsedAt: Date(timeIntervalSince1970: 3000))
        assignments.upsert(different)
        XCTAssertEqual(assignments.count, 2)
    }

    // MARK: - Integration: capture records assignment

    func testCaptureRecordsSlotAssignment() throws {
        let display = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            serialNumber: 42,
            portIdentifier: 3,
            isBuiltIn: false,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let manager = MockDisplayManager(displays: [display])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        try coordinator.captureCurrentSetup()

        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles[0].knownAssignments.count, 1)
        XCTAssertEqual(profiles[0].knownAssignments[0].entries.count, 1)
        XCTAssertEqual(profiles[0].knownAssignments[0].entries[0].serialNumber, 42)
        XCTAssertEqual(profiles[0].knownAssignments[0].entries[0].portIdentifier, 3)
    }
}

// MARK: - Test helpers

private final class MockDisplayManager: DisplayManaging {
    var displays: [DisplaySnapshot]
    var applied: [DisplayConfiguration] = []

    init(displays: [DisplaySnapshot]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplaySnapshot] { displays }
    func apply(configuration: DisplayConfiguration, to display: DisplaySnapshot) throws {
        applied.append(configuration)
    }
}

private final class InMemoryProfileStore: MonitorProfileStoring {
    private var profiles: [MonitorSetProfile] = []
    func loadProfiles() throws -> [MonitorSetProfile] { profiles }
    func saveProfiles(_ profiles: [MonitorSetProfile]) throws { self.profiles = profiles }
}

private struct ImmediateSleepManager: SleepManaging {
    func sleep(milliseconds: UInt64) async {}
}
