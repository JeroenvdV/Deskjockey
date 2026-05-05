import XCTest
@testable import DeskjockeyCore

final class ProfileStoreTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        // Create a temporary directory for test profiles
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskjockeyTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir
    }

    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    private func profileFileURL() -> URL {
        tempDirectory.appendingPathComponent("profiles.json")
    }

    func testLoadProfilesReturnsEmptyArrayWhenFileNotExists() throws {
        let store = JSONProfileStore(fileURL: profileFileURL())
        
        let profiles = try store.loadProfiles()
        
        XCTAssertTrue(profiles.isEmpty)
    }

    func testSaveProfilesCreatesFile() throws {
        let store = JSONProfileStore(fileURL: profileFileURL())
        let profile = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Testx1"),
            slots: [
                MonitorSlotProfile(
                    modelName: "Test Display",
                    slotIndex: 0,
                    targetFrame: DisplayFrame(
                        origin: DisplayPoint(x: 0, y: 0),
                        size: DisplaySize(width: 1920, height: 1080)
                    ),
                    targetResolution: DisplaySize(width: 1920, height: 1080)
                )
            ],
            updatedAt: Date(),
            lastUsedAt: nil,
            resolutionSignature: ResolutionSetSignature(rawValue: "1920x1080x1")
        )
        
        try store.saveProfiles([profile])
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileFileURL().path))
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

    func testSaveProfilesOverwritesExistingFile() throws {
        let store = JSONProfileStore(fileURL: profileFileURL())
        
        let profile1 = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Test1x1"),
            slots: [],
            updatedAt: Date()
        )
        let profile2 = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Test2x1"),
            slots: [],
            updatedAt: Date()
        )
        
        try store.saveProfiles([profile1])
        try store.saveProfiles([profile2])
        
        let loadedProfiles = try store.loadProfiles()
        
        XCTAssertEqual(loadedProfiles.count, 1)
        XCTAssertEqual(loadedProfiles[0].signature, profile2.signature)
    }

    func testSaveProfilesCreatesParentDirectories() throws {
        let nestedDir = tempDirectory
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
        let nestedFile = nestedDir.appendingPathComponent("profiles.json")
        
        // Ensure the directory doesn't exist initially
        try? FileManager.default.removeItem(at: nestedDir)
        
        let store = JSONProfileStore(fileURL: nestedFile)
        let profile = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Testx1"),
            slots: [],
            updatedAt: Date()
        )
        
        try store.saveProfiles([profile])
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: nestedFile.path))
    }

    func testLoadProfilesWithMultipleProfiles() throws {
        let store = JSONProfileStore(fileURL: profileFileURL())
        
        let profiles = (0..<5).map { i in
            MonitorSetProfile(
                signature: MonitorSetSignature(rawValue: "Model\(i)x1"),
                slots: [],
                updatedAt: Date()
            )
        }
        
        try store.saveProfiles(profiles)
        let loadedProfiles = try store.loadProfiles()
        
        XCTAssertEqual(loadedProfiles.count, 5)
    }

    func testLoadProfilesWithEmptyArray() throws {
        let store = JSONProfileStore(fileURL: profileFileURL())
        
        try store.saveProfiles([])
        let loadedProfiles = try store.loadProfiles()
        
        XCTAssertTrue(loadedProfiles.isEmpty)
    }

    func testLoadProfilesWithEmptyFile() throws {
        let fileURL = profileFileURL()
        try "[]".data(using: .utf8)?.write(to: fileURL)
        
        let store = JSONProfileStore(fileURL: fileURL)
        let profiles = try store.loadProfiles()
        
        XCTAssertTrue(profiles.isEmpty)
    }

    func testSaveProfilesWithEmptyArray() throws {
        let store = JSONProfileStore(fileURL: profileFileURL())
        
        try store.saveProfiles([])
        
        // File should still exist and be valid
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileFileURL().path))
        let data = try Data(contentsOf: profileFileURL())
        let decoded = try JSONDecoder().decode([MonitorSetProfile].self, from: data)
        XCTAssertTrue(decoded.isEmpty)
    }

    func testLoadProfilesThrowsOnInvalidJSON() {
        let fileURL = profileFileURL()
        try? "invalid json".data(using: .utf8)?.write(to: fileURL)
        
        let store = JSONProfileStore(fileURL: fileURL)
        
        XCTAssertThrowsError(try store.loadProfiles())
    }

    func testLoadProfilesThrowsOnCorruptedData() {
        let fileURL = profileFileURL()
        try? "[{ \"invalid\": ".data(using: .utf8)?.write(to: fileURL)
        
        let store = JSONProfileStore(fileURL: fileURL)
        
        XCTAssertThrowsError(try store.loadProfiles())
    }

    func testInMemoryProfileStoreLoadSave() throws {
        let store = InMemoryProfileStoreForTests()
        
        let profile = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Testx1"),
            slots: [],
            updatedAt: Date()
        )
        
        try store.saveProfiles([profile])
        let loaded = try store.loadProfiles()
        
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].signature, profile.signature)
    }

    func testInMemoryProfileStoreOverwrite() throws {
        let store = InMemoryProfileStoreForTests()
        
        let profile1 = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Test1x1"),
            slots: [],
            updatedAt: Date()
        )
        let profile2 = MonitorSetProfile(
            signature: MonitorSetSignature(rawValue: "Test2x1"),
            slots: [],
            updatedAt: Date()
        )
        
        try store.saveProfiles([profile1])
        try store.saveProfiles([profile2])
        
        let loaded = try store.loadProfiles()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].signature, profile2.signature)
    }
}

// Test helper - move to test utilities or keep here
private final class InMemoryProfileStoreForTests: MonitorProfileStoring {
    private var profiles: [MonitorSetProfile] = []

    func loadProfiles() throws -> [MonitorSetProfile] {
        profiles
    }

    func saveProfiles(_ profiles: [MonitorSetProfile]) throws {
        self.profiles = profiles
    }
}
