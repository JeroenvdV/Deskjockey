import XCTest
@testable import DeskjockeyCore

final class ResizeLayoutTests: XCTestCase {
    private func builtIn(x: Int = 0, y: Int = 0, width: Int = 1710, height: Int = 1107) -> DisplaySnapshot {
        DisplaySnapshot(
            runtimeID: "1",
            modelName: "Built-in Retina Display",
            serialNumber: 4251086178,
            portIdentifier: 0,
            isBuiltIn: true,
            frame: DisplayFrame(origin: .init(x: x, y: y), size: .init(width: width, height: height)),
            resolution: .init(width: width * 2, height: height * 2)
        )
    }

    private func dell(x: Int, y: Int, width: Int, height: Int) -> DisplaySnapshot {
        DisplaySnapshot(
            runtimeID: "2",
            modelName: "DELL P3225QE",
            serialNumber: 892744012,
            portIdentifier: 1,
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: x, y: y), size: .init(width: width, height: height)),
            resolution: .init(width: width * 2, height: height * 2)
        )
    }

    private func makeCoordinator(
        _ manager: MockDisplayManager,
        _ store: InMemoryProfileStore
    ) -> DisplayConfigurationCoordinator {
        DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
    }

    private func savedDellFrame(_ store: InMemoryProfileStore) throws -> DisplayFrame? {
        try store.loadProfiles().first?.slots.first { $0.modelName == "DELL P3225QE" }?.targetFrame
    }

    func testResizedDisplayStaysAboveItsNeighbor() throws {
        let manager = MockDisplayManager(displays: [builtIn(), dell(x: -513, y: -1692, width: 3008, height: 1692)])
        let store = InMemoryProfileStore()
        let coordinator = makeCoordinator(manager, store)
        try coordinator.captureCurrentSetup()

        // User picks 1920x1080; macOS moves the Dell to the right of the laptop.
        manager.displays = [builtIn(), dell(x: 1710, y: -1080, width: 1920, height: 1080)]
        try coordinator.configurationDidChange()

        XCTAssertEqual(manager.moved, [["2": DisplayPoint(x: -18, y: -1080)]])
        XCTAssertEqual(try savedDellFrame(store)?.origin, DisplayPoint(x: -18, y: -1080))
    }

    func testSwitchingBackRestoresTheLayoutSavedForThatSize() throws {
        let manager = MockDisplayManager(displays: [builtIn(), dell(x: -513, y: -1692, width: 3008, height: 1692)])
        let store = InMemoryProfileStore()
        let coordinator = makeCoordinator(manager, store)
        try coordinator.captureCurrentSetup()

        manager.displays = [builtIn(), dell(x: 1710, y: -1080, width: 1920, height: 1080)]
        try coordinator.configurationDidChange()

        // User drags the Dell to where they want it at 1920x1080.
        manager.displays = [builtIn(), dell(x: 100, y: -1080, width: 1920, height: 1080)]
        try coordinator.configurationDidChange()
        XCTAssertEqual(manager.moved.count, 1)

        manager.displays = [builtIn(), dell(x: 1710, y: -1692, width: 3008, height: 1692)]
        try coordinator.configurationDidChange()
        XCTAssertEqual(manager.moved.last, ["2": DisplayPoint(x: -513, y: -1692)])

        manager.displays = [builtIn(), dell(x: 1710, y: -1080, width: 1920, height: 1080)]
        try coordinator.configurationDidChange()
        XCTAssertEqual(manager.moved.last, ["2": DisplayPoint(x: 100, y: -1080)])
    }

    func testFlushEdgeStaysFlushAfterResize() throws {
        let manager = MockDisplayManager(displays: [builtIn(), dell(x: 0, y: -1692, width: 3008, height: 1692)])
        let store = InMemoryProfileStore()
        let coordinator = makeCoordinator(manager, store)
        try coordinator.captureCurrentSetup()

        manager.displays = [builtIn(), dell(x: 1710, y: -1080, width: 1920, height: 1080)]
        try coordinator.configurationDidChange()

        XCTAssertEqual(manager.moved, [["2": DisplayPoint(x: 0, y: -1080)]])
    }

    func testResizingTheMainDisplayMovesTheOthersAroundIt() throws {
        let manager = MockDisplayManager(displays: [builtIn(), dell(x: -513, y: -1692, width: 3008, height: 1692)])
        let store = InMemoryProfileStore()
        let coordinator = makeCoordinator(manager, store)
        try coordinator.captureCurrentSetup()

        // The laptop stays at (0, 0) because it is the main display.
        manager.displays = [builtIn(width: 1440, height: 932), dell(x: -513, y: -1692, width: 3008, height: 1692)]
        try coordinator.configurationDidChange()

        XCTAssertEqual(manager.moved, [["2": DisplayPoint(x: -669, y: -1692)]])
    }

    func testRearrangingWithoutResizeOnlySaves() throws {
        let manager = MockDisplayManager(displays: [builtIn(), dell(x: -513, y: -1692, width: 3008, height: 1692)])
        let store = InMemoryProfileStore()
        let coordinator = makeCoordinator(manager, store)
        try coordinator.captureCurrentSetup()

        manager.displays = [builtIn(), dell(x: 1710, y: -500, width: 3008, height: 1692)]
        try coordinator.configurationDidChange()

        XCTAssertTrue(manager.moved.isEmpty)
        XCTAssertEqual(try savedDellFrame(store)?.origin, DisplayPoint(x: 1710, y: -500))
        XCTAssertEqual(try store.loadProfiles().first?.savedLayouts.count, 1)
    }

    func testProfilesWithoutSavedLayoutsStillDecode() throws {
        let json = """
        [{"signatureRawValue": "DELL P3225QEx1", "slots": [], "updatedAt": 0}]
        """
        let profiles = try JSONDecoder().decode([MonitorSetProfile].self, from: Data(json.utf8))
        XCTAssertEqual(profiles.first?.savedLayouts, [])
    }
}
