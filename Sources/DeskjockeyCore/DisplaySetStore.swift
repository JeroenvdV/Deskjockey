import Foundation

public struct DisplaySetDatabase: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var classes: [DisplaySetClass]
    public var legacyProfiles: [LegacyProfile]

    // Keep the version-two wire key while the domain uses display set classes.
    enum CodingKeys: String, CodingKey {
        case schemaVersion, legacyProfiles
        case classes = "profiles"
    }

    public init(classes: [DisplaySetClass] = [], legacyProfiles: [LegacyProfile] = []) {
        schemaVersion = 2; self.classes = classes; self.legacyProfiles = legacyProfiles
    }
}

public protocol DisplaySetStoring {
    func loadDatabase() throws -> DisplaySetDatabase
    func saveDatabase(_ database: DisplaySetDatabase) throws
}

/// Versioned storage preserves legacy evidence and refuses concurrent external overwrites.
public final class JSONDisplaySetStore: DisplaySetStoring {
    private let fileURL: URL
    private var baseline: Data?
    private var hasLoaded = false
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func loadDatabase() throws -> DisplaySetDatabase {
        let data = try readData()
        let database = try data.map(decode) ?? DisplaySetDatabase()
        baseline = data
        hasLoaded = true
        return database
    }

    public func saveDatabase(_ database: DisplaySetDatabase) throws {
        try Self.validate(database)
        let current = try readData()
        if hasLoaded && current != baseline { throw DisplaySetError.operationFailed("display_set_database_changed_externally") }
        if let current {
            _ = try decode(current)
            if current.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
                var backup = fileURL.appendingPathExtension("v1-backup")
                if FileManager.default.fileExists(atPath: backup.path), try Data(contentsOf: backup) != current {
                    backup = fileURL.appendingPathExtension("v1-backup.\(UUID().uuidString)")
                }
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try current.write(to: backup, options: .withoutOverwriting)
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(database)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        baseline = data
        hasLoaded = true
    }

    private func readData() throws -> Data? {
        do { return try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    private func decode(_ data: Data) throws -> DisplaySetDatabase {
        let decoder = JSONDecoder()
        let database: DisplaySetDatabase
        if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 91 {
            database = DisplaySetDatabase(legacyProfiles: try decoder.decode([LegacyProfile].self, from: data))
        } else {
            database = try decoder.decode(DisplaySetDatabase.self, from: data)
        }
        try Self.validate(database)
        return database
    }

    public static func validate(_ database: DisplaySetDatabase) throws {
        guard database.schemaVersion == 2 else { throw DisplaySetError.operationFailed("unsupported_schema_version") }
        guard Set(database.classes.map(\.classID)).count == database.classes.count else {
            throw DisplaySetError.operationFailed("duplicate_display_set_classes")
        }
        for displaySetClass in database.classes {
            try ScreenConfigurationLogic.validate(displaySetClass.configuration)
            var keys = Set<[DisplayDeviceID]>()
            for instance in displaySetClass.instances {
                guard keys.insert(instance.devices).inserted,
                      instance.assignments.count == displaySetClass.configuration.slots.count,
                      Set(instance.devices).count == instance.devices.count,
                      Set(instance.assignments.map(\.slotID)) == Set(displaySetClass.configuration.slots.map(\.id)),
                      instance.assignments.allSatisfy({ entry in
                          entry.deviceID.serialNumber != 0 && displaySetClass.configuration.slots.contains {
                              $0.id == entry.slotID && $0.modelID == entry.deviceID.modelID
                          }
                      }) else { throw DisplaySetError.operationFailed("invalid_instance_record") }
            }
        }
    }
}
