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

    /// Tests that two identical monitors at a new desk get correct slot assignments
    /// via port matching. Original monitors (serials 100, 200) were on ports 5, 7.
    /// New monitors (serials 300, 400) are on the same ports → port match assigns
    /// the same slots → correct positions applied.
    func testReapplyMatchesNewRuntimeIDsForIdenticalHardware() async throws {
        let store = InMemoryProfileStore()

        let originalLeft = DisplaySnapshot(
            runtimeID: "ORIG-LEFT",
            modelName: "Dell U2405",
            serialNumber: 100,
            portIdentifier: 5,
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: -1920, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1920, height: 1200)
        )
        let originalRight = DisplaySnapshot(
            runtimeID: "ORIG-RIGHT",
            modelName: "Dell U2405",
            serialNumber: 200,
            portIdentifier: 7,
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

        // New desk: same model, different serials, but same port identifiers.
        // Port matching should assign the same slots.
        let liveRightNow = DisplaySnapshot(
            runtimeID: "NEW-B",
            modelName: "Dell U2405",
            serialNumber: 400,
            portIdentifier: 7,
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
            resolution: .init(width: 1280, height: 800)
        )
        let liveLeftNow = DisplaySnapshot(
            runtimeID: "NEW-A",
            modelName: "Dell U2405",
            serialNumber: 300,
            portIdentifier: 5,
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

    /// Reproduces the real-world sequence from the logs:
    /// 1. Profile exists from a previous session
    /// 2. Monitor plugs in → monitorSetDidChange() applies profile + sets lastUsedAt
    /// 3. macOS settles → captureCurrentSetup() re-saves the arrangement
    /// lastUsedAt must survive step 3.
    func testApplyThenRecapturePreservesLastUsedAt() async throws {
        let store = InMemoryProfileStore()

        // Previous session: profile was captured with a specific arrangement
        let builtIn = DisplaySnapshot(
            runtimeID: "1",
            modelName: "Built-in Retina Display",
            isBuiltIn: true,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1243)),
            resolution: .init(width: 3840, height: 2486)
        )
        let dell = DisplaySnapshot(
            runtimeID: "3",
            modelName: "DELL P3225QE",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: -1013, y: -2160), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        let captureManager = MockDisplayManager(displays: [builtIn, dell])
        let captureCoordinator = DisplayConfigurationCoordinator(
            displayManager: captureManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        try captureCoordinator.captureCurrentSetup()

        // Step 2: Monitor plugs in at a new desk — monitorSetDidChange() applies and sets lastUsedAt
        let liveDell = DisplaySnapshot(
            runtimeID: "2",
            modelName: "DELL P3225QE",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 1920, y: 0), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        let applyManager = MockDisplayManager(displays: [builtIn, liveDell])
        let applyCoordinator = DisplayConfigurationCoordinator(
            displayManager: applyManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        await applyCoordinator.monitorSetDidChange()

        // Verify lastUsedAt was set by monitorSetDidChange
        let afterApply = try store.loadProfiles()
        let profileAfterApply = afterApply.first { $0.signatureRawValue.contains("P3225QE") }!
        XCTAssertNotNil(profileAfterApply.lastUsedAt)
        let savedLastUsedAt = profileAfterApply.lastUsedAt

        // Step 3: macOS settles, arrangement may shift — captureCurrentSetup() re-saves
        let settledDell = DisplaySnapshot(
            runtimeID: "2",
            modelName: "DELL P3225QE",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: -1013, y: -2160), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        applyManager.displays = [builtIn, settledDell]
        try applyCoordinator.captureCurrentSetup()

        // lastUsedAt must survive the re-capture
        let afterRecapture = try store.loadProfiles()
        let profileAfterRecapture = afterRecapture.first { $0.signatureRawValue.contains("P3225QE") }!
        XCTAssertEqual(profileAfterRecapture.lastUsedAt, savedLastUsedAt)
        // But the arrangement should be updated
        let dellSlot = profileAfterRecapture.slots.first { $0.modelName == "DELL P3225QE" }!
        XCTAssertEqual(dellSlot.targetFrame.origin.x, -1013)
        XCTAssertEqual(dellSlot.targetFrame.origin.y, -2160)
    }

    /// Reproduces the user's real scenario: two Dell monitors with identical
    /// resolutions but different model names (P3225QE at home, P3223QE at office).
    /// Both have resolution signature "3840x2486x1|3840x2160x1".
    /// After using P3225QE, findMostRecentMatchingProfileByResolution() from a
    /// third setup should prefer P3225QE over P3223QE because its lastUsedAt is set.
    func testLastUsedAtDisambiguatesProfilesWithSameResolutionSignature() async throws {
        let store = InMemoryProfileStore()

        let builtIn = DisplaySnapshot(
            runtimeID: "1",
            modelName: "Built-in Retina Display",
            isBuiltIn: true,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1243)),
            resolution: .init(width: 3840, height: 2486)
        )

        // Profile A: DELL P3225QE (home) — captured long ago
        let dellHome = DisplaySnapshot(
            runtimeID: "2",
            modelName: "DELL P3225QE",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: -1013, y: -2160), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        let homeManager = MockDisplayManager(displays: [builtIn, dellHome])
        let homeCoordinator = DisplayConfigurationCoordinator(
            displayManager: homeManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        try homeCoordinator.captureCurrentSetup()

        // Profile B: DELL P3223QE (office) — captured more recently
        let dellOffice = DisplaySnapshot(
            runtimeID: "3",
            modelName: "DELL P3223QE",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 1920, y: 0), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        let officeManager = MockDisplayManager(displays: [builtIn, dellOffice])
        let officeCoordinator = DisplayConfigurationCoordinator(
            displayManager: officeManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0,
            now: { Date(timeIntervalSince1970: 2_000_000) }
        )
        try officeCoordinator.captureCurrentSetup()

        // Both profiles have the same resolution signature
        let profiles = try store.loadProfiles()
        let homeProfile = profiles.first { $0.signatureRawValue.contains("P3225QE") }!
        let officeProfile = profiles.first { $0.signatureRawValue.contains("P3223QE") }!
        XCTAssertEqual(homeProfile.resolutionSignature, officeProfile.resolutionSignature)

        // Now use the home setup: monitorSetDidChange() sets lastUsedAt, then recapture
        let useHomeManager = MockDisplayManager(displays: [builtIn, dellHome])
        let useHomeCoordinator = DisplayConfigurationCoordinator(
            displayManager: useHomeManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0,
            now: { Date(timeIntervalSince1970: 3_000_000) }
        )
        await useHomeCoordinator.monitorSetDidChange()
        try useHomeCoordinator.captureCurrentSetup()

        // Verify: home profile now has lastUsedAt, office does not
        let afterUse = try store.loadProfiles()
        let homeAfterUse = afterUse.first { $0.signatureRawValue.contains("P3225QE") }!
        let officeAfterUse = afterUse.first { $0.signatureRawValue.contains("P3223QE") }!
        XCTAssertNotNil(homeAfterUse.lastUsedAt)
        XCTAssertNil(officeAfterUse.lastUsedAt)

        // From a third monitor setup with the same resolution, the home profile
        // should be preferred because it has a more recent lastUsedAt
        let thirdDell = DisplaySnapshot(
            runtimeID: "4",
            modelName: "DELL P3225QE-NEW",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        let thirdManager = MockDisplayManager(displays: [builtIn, thirdDell])
        let thirdCoordinator = DisplayConfigurationCoordinator(
            displayManager: thirdManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        let mostRecent = thirdCoordinator.findMostRecentMatchingProfileByResolution()
        XCTAssertNotNil(mostRecent)
        XCTAssertTrue(mostRecent!.signatureRawValue.contains("P3225QE"),
            "Should prefer the profile with lastUsedAt set, got: \(mostRecent!.signatureRawValue)")
    }

    /// Migration must recompute resolution signatures written by older versions
    /// that used area-descending ordering. The canonical ordering is now
    /// DisplaySize.Comparable (width ascending, then height ascending).
    func testMigrateRecomputesOldAreaDescendingSignature() throws {
        let store = InMemoryProfileStore()
        let manager = MockDisplayManager(displays: [])
        let coordinator = DisplayConfigurationCoordinator(
            displayManager: manager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        // Profile with old area-descending signature: 3840x2486 (larger area) before 3840x2160
        let oldProfile = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Built-in Retina Displayx1|DELL P3225QEx1"),
            slots: [
                MonitorSlotProfile(
                    modelName: "Built-in Retina Display",
                    slotIndex: 0,
                    targetFrame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1243)),
                    targetResolution: .init(width: 3840, height: 2486)
                ),
                MonitorSlotProfile(
                    modelName: "DELL P3225QE",
                    slotIndex: 0,
                    targetFrame: DisplayFrame(origin: .init(x: -1013, y: -2160), size: .init(width: 3840, height: 2160)),
                    targetResolution: .init(width: 3840, height: 2160)
                ),
            ],
            updatedAt: Date()
        )
        // Manually set the OLD area-descending signature
        var mutable = oldProfile
        mutable.resolutionSignatureRawValue = "3840x2486x1|3840x2160x1"
        try store.saveProfiles([mutable])

        coordinator.migrateProfilesIfNeeded()

        let profiles = try store.loadProfiles()
        XCTAssertEqual(profiles.count, 1)
        // Canonical ordering: width ascending, then height ascending
        // Both have width 3840, so sort by height: 2160 < 2486
        XCTAssertEqual(profiles[0].resolutionSignature?.rawValue, "3840x2160x1|3840x2486x1")
    }

    /// Copy Similar Setup must pair by resolution, not by position.
    /// Source: built-in at origin + Dell above-left (like user's home arrangement).
    /// Target: built-in at origin + Dell to-the-right (different physical layout).
    /// The Dell slot (3840x2160) must pair with the Dell display (3840x2160),
    /// not cross-match with the built-in (3840x2486).
    func testCopySimilarSetupPairsByResolutionNotPosition() throws {
        let store = InMemoryProfileStore()

        // Source profile: home arrangement — Dell above-left of built-in
        let sourceBuiltIn = DisplaySnapshot(
            runtimeID: "1",
            modelName: "Built-in Retina Display",
            isBuiltIn: true,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1243)),
            resolution: .init(width: 3840, height: 2486)
        )
        let sourceDell = DisplaySnapshot(
            runtimeID: "2",
            modelName: "DELL P3225QE",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: -1013, y: -2160), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        let sourceManager = MockDisplayManager(displays: [sourceBuiltIn, sourceDell])
        let sourceCoordinator = DisplayConfigurationCoordinator(
            displayManager: sourceManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )
        try sourceCoordinator.captureCurrentSetup()

        // Target displays: office arrangement — Dell to the right of built-in
        // Different model name but same resolutions → same resolution signature
        let targetBuiltIn = DisplaySnapshot(
            runtimeID: "10",
            modelName: "Built-in Retina Display",
            isBuiltIn: true,
            frame: DisplayFrame(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1243)),
            resolution: .init(width: 3840, height: 2486)
        )
        let targetDell = DisplaySnapshot(
            runtimeID: "11",
            modelName: "DELL P3223QE",
            isBuiltIn: false,
            frame: DisplayFrame(origin: .init(x: 1920, y: 0), size: .init(width: 3840, height: 2160)),
            resolution: .init(width: 3840, height: 2160)
        )
        let targetManager = MockDisplayManager(displays: [targetBuiltIn, targetDell])
        let targetCoordinator = DisplayConfigurationCoordinator(
            displayManager: targetManager,
            profileStore: store,
            sleepManager: ImmediateSleepManager(),
            reapplyDelayMilliseconds: 0
        )

        // Should find the source profile as a match
        let match = targetCoordinator.findMostRecentMatchingProfileByResolution()
        XCTAssertNotNil(match)

        // Copy the similar setup
        try targetCoordinator.copyProfileFromSimilarSetup(sourceProfile: match!)

        // Verify: the Dell slot should have Dell's resolution, not built-in's
        let profiles = try store.loadProfiles()
        let newProfile = profiles.first { $0.signatureRawValue.contains("P3223QE") }!
        
        let dellSlot = newProfile.slots.first { $0.modelName == "DELL P3223QE" }!
        XCTAssertEqual(dellSlot.targetResolution, DisplaySize(width: 3840, height: 2160),
            "Dell slot must get Dell's resolution (3840x2160), not built-in's (3840x2486)")
        XCTAssertEqual(dellSlot.targetFrame.origin.x, -1013,
            "Dell slot must get the source Dell's position")
        
        let builtInSlot = newProfile.slots.first { $0.modelName == "Built-in Retina Display" }!
        XCTAssertEqual(builtInSlot.targetResolution, DisplaySize(width: 3840, height: 2486),
            "Built-in slot must get built-in's resolution (3840x2486), not Dell's (3840x2160)")
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
