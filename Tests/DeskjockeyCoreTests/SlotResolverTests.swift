import XCTest
@testable import DeskjockeyCore

final class SlotResolverTests: XCTestCase {

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
