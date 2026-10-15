import Foundation

/// Version-one DTOs retain historical evidence without rewriting names or assigning hardware IDs offline.
public struct LegacyProfile: Codable, Hashable, Sendable {
    public var signatureRawValue: String
    public var slots: [LegacySlot]
    public var knownAssignments: [LegacyAssignment]
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var resolutionSignatureRawValue: String?
    enum CodingKeys: String, CodingKey {
        case signatureRawValue, slots, knownAssignments, updatedAt, lastUsedAt, resolutionSignatureRawValue
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signatureRawValue = try c.decode(String.self, forKey: .signatureRawValue)
        slots = try c.decode([LegacySlot].self, forKey: .slots)
        knownAssignments = try c.decodeIfPresent([LegacyAssignment].self, forKey: .knownAssignments) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        resolutionSignatureRawValue = try c.decodeIfPresent(String.self, forKey: .resolutionSignatureRawValue)
    }
}

public struct LegacySlot: Codable, Hashable, Sendable {
    public var modelName: String
    public var slotIndex: Int
    public var targetFrame: DisplayFrame
    public var targetResolution: DisplaySize
}
public struct LegacyAssignment: Codable, Hashable, Sendable {
    public var entries: [LegacyEntry]
    public var lastUsedAt: Date
}
public struct LegacyEntry: Codable, Hashable, Sendable {
    public var modelName: String
    public var slotIndex: Int
    public var serialNumber: UInt32
    public var portIdentifier: UInt32
}

public enum LegacyProfileMigration {
    /// Only live, one-to-one evidence can bridge a legacy profile to identified models.
    /// Every original remains in the database, including conflicting layouts and older instances.
    public static func convert(_ legacy: LegacyProfile, displays: [DisplaySnapshot]) -> (DisplaySetClass, [String: Int])? {
        guard legacy.slots.count == displays.count, !displays.isEmpty else { return nil }
        var available = displays
        var slots: [DisplaySlot] = []
        var mapping: [String: Int] = [:]
        for (id, slot) in legacy.slots.enumerated() {
            let knownSerials = Set(legacy.knownAssignments.flatMap(\.entries).filter {
                $0.modelName == slot.modelName && $0.slotIndex == slot.slotIndex && $0.serialNumber != 0
            }.map(\.serialNumber))
            let named = available.filter {
                $0.displayName == slot.modelName || ($0.isBuiltIn && ["Built-in Display", "Built-in Retina Display"].contains(slot.modelName))
            }
            let serialMatches = named.filter { knownSerials.contains($0.serialNumber) }
            let candidates = serialMatches.count == 1 ? serialMatches : named
            guard candidates.count == 1, let display = candidates.first, let modelID = display.modelID else { return nil }
            available.removeAll { $0.runtimeID == display.runtimeID }
            mapping[display.runtimeID] = id
            slots.append(DisplaySlot(id: id, modelID: modelID,
                                     targetFrame: slot.targetFrame,
                                     targetMode: DisplayMode(logicalSize: slot.targetFrame.size, pixelSize: slot.targetResolution),
                                     isBuiltIn: display.isBuiltIn))
        }
        let mains = slots.filter { $0.targetFrame.origin == DisplayPoint(x: 0, y: 0) }
        guard mains.count == 1, let main = mains.first else { return nil }
        let configuration = ScreenConfiguration(slots: slots, mainSlotID: main.id)
        guard (try? ScreenConfigurationLogic.validate(configuration)) != nil else { return nil }
        return (DisplaySetClass(configuration: configuration, updatedAt: legacy.updatedAt, lastUsedAt: legacy.lastUsedAt), mapping)
    }
}
