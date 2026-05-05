import XCTest
@testable import DeskjockeyCore

final class DisplayConfigurationCoordinatorTests: XCTestCase {
    func testCaptureStoresProfileByModelSet() throws {
        let builtIn = DisplaySnapshot(
            runtimeID: "A",
            modelName: "MacBook Pro Display",
            isBuiltIn: true,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1728, height: 1117)),
            resolution: .init(width: 1728, height: 1117)
        )
        let dell = DisplaySnapshot(
            runtimeID: "B",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 1728, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let displayManager = MockDisplayManager(displays: [builtIn, dell])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: displayManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        try coordinator.captureCurrentSetup()

        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(
            profiles[0].signature,
            MonitorSetSignature(rawValue: "Dell U2405x1|MacBook Pro Displayx1")
        )
        XCTAssertEqual(profiles[0].slots.count, 2)
    }

    func testReapplyMatchesNewRuntimeIDsForIdenticalHardware() async throws {
        let store = InMemoryProfileStore()

        let originalLeft = DisplaySnapshot(
            runtimeID: "ORIG-LEFT",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: -1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let originalRight = DisplaySnapshot(
            runtimeID: "ORIG-RIGHT",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let captureManager = MockDisplayManager(displays: [originalLeft, originalRight])
        let captureCoordinator = DisplayConfigurationCoordinator(
            displayManager: captureManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        try captureCoordinator.captureCurrentSetup()

        // Simulate moving to a new desk: same model monitors, different runtime IDs and port order.
        let liveRightNow = DisplaySnapshot(
            runtimeID: "NEW-B",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1280, height: 800)
        )
        let liveLeftNow = DisplaySnapshot(
            runtimeID: "NEW-A",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: -1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1024, height: 768)
        )
        let reapplyManager = MockDisplayManager(displays: [liveRightNow, liveLeftNow])
        let reapplyCoordinator = DisplayConfigurationCoordinator(
            displayManager: reapplyManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        await reapplyCoordinator.monitorSetDidChange()

        XCTAssertEqual(reapplyManager.applied.count, 2)

        let appliedByRuntime = Dictionary(uniqueKeysWithValues: reapplyManager.applied.map { ($0.runtimeID, $0) })
        XCTAssertEqual(appliedByRuntime["NEW-A"]?.targetFrame.origin.x, -1920)
        XCTAssertEqual(appliedByRuntime["NEW-B"]?.targetFrame.origin.x, 0)
        XCTAssertEqual(appliedByRuntime["NEW-A"]?.targetResolution.width, 1920)
        XCTAssertEqual(appliedByRuntime["NEW-B"]?.targetResolution.width, 1920)
    }

    func testNoProfileMeansNoApply() async {
        let manager = MockDisplayManager(displays: [
            DisplaySnapshot(
                runtimeID: "X",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            )
        ])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        await coordinator.monitorSetDidChange()

        XCTAssertEqual(manager.applied.count, 0)
    }

    func testCaptureOverwritesExistingProfileForSameModelSet() throws {
        let display = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
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
        var profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].slots.first?.targetResolution.width, 1920)

        manager.displays = [
            DisplaySnapshot(
                runtimeID: "D1",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: DisplayFrame(origin: .init(x: 100, y: 50), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1600, height: 1000)
            )
        ]
        try coordinator.captureCurrentSetup()

        profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].slots.first?.targetFrame.origin.x, 100)
        XCTAssertEqual(profiles[0].slots.first?.targetResolution.width, 1600)
    }

    func testCaptureWithNoDisplaysThrows() {
        let manager = MockDisplayManager(displays: [])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        XCTAssertThrowsError(try coordinator.captureCurrentSetup()) { error in
            XCTAssertTrue(error is ProfileError)
        }
    }

    func testHasSavedProfileReturnsFalseWhenEmpty() {
        let manager = MockDisplayManager(displays: [
            DisplaySnapshot(
                runtimeID: "X",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            )
        ])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        XCTAssertFalse(coordinator.hasSavedProfile())
    }

    func testHasSavedProfileReturnsTrueAfterCapture() throws {
        let manager = MockDisplayManager(displays: [
            DisplaySnapshot(
                runtimeID: "X",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            )
        ])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        try coordinator.captureCurrentSetup()
        XCTAssertTrue(coordinator.hasSavedProfile())
    }

    func testDisplaySummariesOrderedLeftToRight() throws {
        let right = DisplaySnapshot(
            runtimeID: "R",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let left = DisplaySnapshot(
            runtimeID: "L",
            modelName: "MacBook Pro Display",
            isBuiltIn: true,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1728, height: 1117)),
            resolution: .init(width: 1728, height: 1117)
        )
        let manager = MockDisplayManager(displays: [right, left])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        let summaries = coordinator.displaySummaries()
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(summaries[0].modelName, "MacBook Pro Display")
        XCTAssertTrue(summaries[0].isBuiltIn)
        XCTAssertEqual(summaries[1].modelName, "Dell U2405")
        XCTAssertFalse(summaries[1].isBuiltIn)
    }

    func testCurrentSetupMatchesSavedAfterCapture() throws {
        let display = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
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

        XCTAssertFalse(coordinator.currentSetupMatchesSaved())

        try coordinator.captureCurrentSetup()
        XCTAssertTrue(coordinator.currentSetupMatchesSaved())

        let summaries = coordinator.displaySummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertTrue(summaries[0].matchesSaved)
    }

    func testCurrentSetupMismatchAfterDisplayChange() throws {
        let original = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let manager = MockDisplayManager(displays: [original])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        try coordinator.captureCurrentSetup()
        XCTAssertTrue(coordinator.currentSetupMatchesSaved())

        // Simulate resolution change
        manager.displays = [
            DisplaySnapshot(
                runtimeID: "D1",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1280, height: 800)
            )
        ]

        XCTAssertFalse(coordinator.currentSetupMatchesSaved())

        let summaries = coordinator.displaySummaries()
        XCTAssertEqual(summaries.count, 1)
        XCTAssertFalse(summaries[0].matchesSaved)
    }

    func testNoDisplaysMeansNoReapply() async {
        let manager = MockDisplayManager(displays: [])
        let store = InMemoryProfileStore()
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        await coordinator.monitorSetDidChange()

        XCTAssertEqual(manager.applied.count, 0)
    }

    func testCopySimilarSetupCreatesNewProfileFromMatchingResolution() throws {
        let store = InMemoryProfileStore()

        // First, create a profile for one setup
        let originalDisplay = DisplaySnapshot(
            runtimeID: "ORIG-1",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let captureManager = MockDisplayManager(displays: [originalDisplay])
        let captureCoordinator = DisplayConfigurationCoordinator(
            displayManager: captureManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        try captureCoordinator.captureCurrentSetup()

        // Now switch to a different setup with the same resolution but different model
        let newDisplay = DisplaySnapshot(
            runtimeID: "NEW-1",
            modelName: "HP Monitor",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let newManager = MockDisplayManager(displays: [newDisplay])
        let newCoordinator = DisplayConfigurationCoordinator(
            displayManager: newManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        // Check that we have a matching resolution profile
        XCTAssertTrue(newCoordinator.hasSimilarSetupByResolution())

        // Copy the similar setup
        if let sourceProfile = newCoordinator.findMostRecentMatchingProfileByResolution() {
            try newCoordinator.copyProfileFromSimilarSetup(sourceProfile: sourceProfile)
        }

        // Verify new profile was created with the new model name
        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.count, 2)
        
        let newProfile = profiles.first { $0.signature.rawValue == "HP Monitorx1" }
        XCTAssertNotNil(newProfile)
        XCTAssertEqual(newProfile?.slots.first?.modelName, "HP Monitor")
        XCTAssertEqual(newProfile?.slots.first?.targetResolution.width, 1920)
    }

    func testFindMostRecentMatchingProfileByResolution() throws {
        let store = InMemoryProfileStore()

        // Create first profile
        let display1 = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Model A",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let manager1 = MockDisplayManager(displays: [display1])
        let coordinator1 = DisplayConfigurationCoordinator(
            displayManager: manager1,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        try coordinator1.captureCurrentSetup()

        // Create second profile with same resolution
        let display2 = DisplaySnapshot(
            runtimeID: "D2",
            modelName: "Model B",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let manager2 = MockDisplayManager(displays: [display2])
        let coordinator2 = DisplayConfigurationCoordinator(
            displayManager: manager2,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0,
            now: { Date.distantPast }  // Older date
        )
        try coordinator2.captureCurrentSetup()

        // Now check from a third setup with same resolution
        let display3 = DisplaySnapshot(
            runtimeID: "D3",
            modelName: "Model C",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let manager3 = MockDisplayManager(displays: [display3])
        let coordinator3 = DisplayConfigurationCoordinator(
            displayManager: manager3,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        // The most recent should be Model A (captured first with Date())
        let mostRecent = coordinator3.findMostRecentMatchingProfileByResolution()
        XCTAssertNotNil(mostRecent)
        XCTAssertEqual(mostRecent?.signature.rawValue, "Model Ax1")
    }

    func testCopySimilarSetupDisabledWhenNoMatch() throws {
        let store = InMemoryProfileStore()

        // Create a profile
        let display = DisplaySnapshot(
            runtimeID: "D1",
            modelName: "Dell U2405",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let manager = MockDisplayManager(displays: [display])
        let captureCoordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        try captureCoordinator.captureCurrentSetup()

        // Check with a different resolution - should have no match
        let differentDisplay = DisplaySnapshot(
            runtimeID: "D2",
            modelName: "HP Monitor",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 2560, height: 1440)),
            resolution: .init(width: 2560, height: 1440)
        )
        let newManager = MockDisplayManager(displays: [differentDisplay])
        let newCoordinator = DisplayConfigurationCoordinator(
            displayManager: newManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        XCTAssertFalse(newCoordinator.hasSimilarSetupByResolution())
        XCTAssertNil(newCoordinator.findMostRecentMatchingProfileByResolution())
    }
}

private final class MockDisplayManager: DisplayManaging {
    var displays: [DisplaySnapshot]
    var applied: [DisplayConfiguration] = []

    init(displays: [DisplaySnapshot]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplaySnapshot] {
        displays
    }

    func apply(configuration: DisplayConfiguration, to display: DisplaySnapshot) throws {
        applied.append(configuration)
    }
}

private final class InMemoryProfileStore: MonitorProfileStoring {
    private var profiles: [MonitorSetProfile] = []

    func loadProfiles() throws -> [MonitorSetProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [MonitorSetProfile]) throws {
        self.profiles = profiles
    }
}

private struct ImmediateSleepManager: SleepManaging {
    func sleep(milliseconds: UInt64) async {}
}
