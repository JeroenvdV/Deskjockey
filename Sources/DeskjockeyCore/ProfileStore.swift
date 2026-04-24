import Foundation

public protocol MonitorProfileStoring {
    func loadProfiles() throws -> [MonitorSetProfile]
    func saveProfiles(_ profiles: [MonitorSetProfile]) throws
}

/// Persists profiles as a JSON array to ~/Library/Application Support/Deskjockey/profiles.json.
/// Uses atomic writes to avoid corruption if the app is killed mid-save.
public struct JSONProfileStore: MonitorProfileStoring {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadProfiles() throws -> [MonitorSetProfile] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([MonitorSetProfile].self, from: data)
    }

    public func saveProfiles(_ profiles: [MonitorSetProfile]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try encoder.encode(profiles)
        try data.write(to: fileURL, options: .atomic)
    }
}
