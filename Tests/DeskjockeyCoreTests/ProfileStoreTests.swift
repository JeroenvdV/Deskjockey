import XCTest
@testable import DeskjockeyCore

final class ProfileStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskjockeyTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func profileFileURL() -> URL {
        tempDirectory.appendingPathComponent("profiles.json")
    }

    func testSaveAndLoadProfilesRoundTrip() throws {
        let store = JSONProfileStore(fileURL: profileFileURL())
        
        let profile = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Dell U2405x1|MacBookx1"),
            slots: [
                MonitorSlotProfile(
                    modelName: "Dell U2405",
                    slotIndex: 0,
                    targetFrame: DisplayFrame(
                        origin: DisplayPoint(x: 0, y: 0),
                        size: DisplaySize(width: 1920, height: 1200)
                    ),
                    targetResolution: DisplaySize(width: 1920, height: 1200)
                ),
                MonitorSlotProfile(
                    modelName: "MacBook",
                    slotIndex: 0,
                    targetFrame: DisplayFrame(
                        origin: DisplayPoint(x: 1920, y: 0),
                        size: DisplaySize(width: 1728, height: 1117)
                    ),
                    targetResolution: DisplaySize(width: 1728, height: 1117)
                )
            ],
            updatedAt: Date(),
            lastUsedAt: Date(),
            resolutionSignature: ResolutionSetSignature(rawValue: "1920x1200x1|1728x1117x1")
        )
        
        try store.saveProfiles([profile])
        let loadedProfiles = try store.loadProfiles()
        
        XCTAssertEqual(loadedProfiles.count, 1)
        XCTAssertEqual(loadedProfiles[0].signature, profile.signature)
        XCTAssertEqual(loadedProfiles[0].slots.count, 2)
        XCTAssertEqual(loadedProfiles[0].slots[0].modelName, "Dell U2405")
        XCTAssertEqual(loadedProfiles[0].slots[1].modelName, "MacBook")
    }

    func testLoadProfilesThrowsOnInvalidJSON() {
        let fileURL = profileFileURL()
        try? "invalid json".data(using: .utf8)?.write(to: fileURL)
        
        let store = JSONProfileStore(fileURL: fileURL)
        
        XCTAssertThrowsError(try store.loadProfiles())
    }
}
