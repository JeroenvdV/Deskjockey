import Foundation

// MARK: - Geometry primitives
// These mirror CGPoint/CGSize/CGRect but are Codable and platform-independent,
// so DeskjockeyCore has no AppKit/CoreGraphics dependency.

public struct DisplayPoint: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct DisplaySize: Codable, Hashable, Sendable, Comparable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Alphabetical ordering by resolution string ("WIDTHxHEIGHT").
    /// This is the canonical ordering for resolution-based pairing across profiles.
    /// Position is output of the application and must never be used as input for ordering.
    public static func < (lhs: DisplaySize, rhs: DisplaySize) -> Bool {
        if lhs.width != rhs.width { return lhs.width < rhs.width }
        return lhs.height < rhs.height
    }
}

public struct DisplayFrame: Codable, Hashable, Sendable {
    public var origin: DisplayPoint
    public var size: DisplaySize

    public init(origin: DisplayPoint, size: DisplaySize) {
        self.origin = origin
        self.size = size
    }
}

// MARK: - Display snapshot

/// A point-in-time capture of a single display's state as seen by the OS.
/// The runtimeID is a CGDirectDisplayID (as String) -- it can change between
/// reboots or when cables are swapped, so we never use it for profile matching.
public struct DisplaySnapshot: Codable, Hashable, Sendable {
    public var runtimeID: String
    public var modelName: String
    public var serialNumber: UInt32
    public var portIdentifier: UInt32
    public var isBuiltIn: Bool
    public var frame: DisplayFrame
    public var resolution: DisplaySize

    public init(
        runtimeID: String,
        modelName: String,
        serialNumber: UInt32 = 0,
        portIdentifier: UInt32 = 0,
        isBuiltIn: Bool,
        frame: DisplayFrame,
        resolution: DisplaySize
    ) {
        self.runtimeID = runtimeID
        self.modelName = modelName
        self.serialNumber = serialNumber
        self.portIdentifier = portIdentifier
        self.isBuiltIn = isBuiltIn
        self.frame = frame
        self.resolution = resolution
    }

    public var normalizedModelName: String {
        Self.normalizeModelName(modelName)
    }

    /// Stable identifier used for profile matching and topology signatures.
    /// Built-in displays are collapsed to a single canonical name because macOS
    /// may report different localized names for the same panel across reboots
    /// (e.g. "Built-in Display" vs "Built-in Retina Display").
    public var matchingModelName: String {
        Self.matchingModelName(modelName: modelName, isBuiltIn: isBuiltIn)
    }

    public static func normalizeModelName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Display" : trimmed
    }

    public static func matchingModelName(modelName: String, isBuiltIn: Bool) -> String {
        if isBuiltIn {
            return "Built-in Display"
        }
        return normalizeModelName(modelName)
    }
}

// MARK: - Display configuration

/// The desired state for a display -- passed to DisplayManaging.apply().
public struct DisplayConfiguration: Codable, Hashable, Sendable {
    public var runtimeID: String
    public var targetFrame: DisplayFrame
    public var targetResolution: DisplaySize

    public init(
        runtimeID: String,
        targetFrame: DisplayFrame,
        targetResolution: DisplaySize
    ) {
        self.runtimeID = runtimeID
        self.targetFrame = targetFrame
        self.targetResolution = targetResolution
    }
}

// MARK: - Signatures and fingerprints

/// Identifies a set of monitors by model name and count, ignoring runtime IDs,
/// cable order, and port assignment. Two setups with the same models produce the
/// same signature, which is used as the key for profile lookup.
/// Example: "Built-in Displayx1|DELL P3223QEx2"
public struct MonitorSetSignature: Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func from(displays: [DisplaySnapshot]) -> MonitorSetSignature {
        let counts = Dictionary(grouping: displays, by: { $0.matchingModelName }).mapValues(\.count)
        let normalized = counts.keys.sorted().map { modelName in
            "\(modelName)x\(counts[modelName] ?? 0)"
        }
        return .init(rawValue: normalized.joined(separator: "|"))
    }
}

/// A more specific fingerprint that includes runtime IDs. Used to detect whether
/// the physical topology actually changed (vs. macOS just firing extra reconfig
/// events for the same set of displays). Not persisted -- only compared in memory.
public struct DisplayTopologyFingerprint: Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func from(displays: [DisplaySnapshot]) -> DisplayTopologyFingerprint {
        let tokens = displays
            .map { "\($0.matchingModelName)#\($0.runtimeID)#\($0.isBuiltIn ? "builtIn" : "external")" }
            .sorted()
        return .init(rawValue: tokens.joined(separator: "|"))
    }
}

/// Identifies a set of monitors by their native resolutions and count, ignoring
/// model names, runtime IDs, cable order, and port assignment. Used for the
/// "Copy Similar Setup" feature to find profiles with matching display resolutions.
/// Example: "1920x1200x1|1728x1117x1"
public struct ResolutionSetSignature: Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func from(displays: [DisplaySnapshot]) -> ResolutionSetSignature {
        let counts = Dictionary(grouping: displays, by: { $0.resolution }).mapValues { $0.count }
        let normalized = counts.keys.sorted().map { resolution in
            "\(resolution.width)x\(resolution.height)x\(counts[resolution] ?? 0)"
        }
        return .init(rawValue: normalized.joined(separator: "|"))
    }
}

// MARK: - Profile storage types

/// A single display's saved arrangement within a profile. Identified by model name
/// and a positional slot index (not runtime ID), so the profile survives cable swaps.
public struct MonitorSlotProfile: Codable, Hashable, Sendable {
    public var modelName: String
    public var slotIndex: Int
    public var targetFrame: DisplayFrame
    public var targetResolution: DisplaySize

    public init(
        modelName: String,
        slotIndex: Int,
        targetFrame: DisplayFrame,
        targetResolution: DisplaySize
    ) {
        self.modelName = DisplaySnapshot.normalizeModelName(modelName)
        self.slotIndex = slotIndex
        self.targetFrame = targetFrame
        self.targetResolution = targetResolution
    }
}

// MARK: - Slot assignments

/// Records which physical monitors occupied which slots during a specific
/// connection event. Identified by the set of serial numbers.
public struct SlotAssignment: Codable, Hashable, Sendable {
    public var entries: [SlotAssignmentEntry]
    public var lastUsedAt: Date

    public init(entries: [SlotAssignmentEntry], lastUsedAt: Date) {
        self.entries = entries
        self.lastUsedAt = lastUsedAt
    }
}

/// Maps a single physical monitor to a slot within a profile.
public struct SlotAssignmentEntry: Codable, Hashable, Sendable {
    public var modelName: String
    public var slotIndex: Int
    public var serialNumber: UInt32
    public var portIdentifier: UInt32

    public init(modelName: String, slotIndex: Int, serialNumber: UInt32, portIdentifier: UInt32) {
        self.modelName = modelName
        self.slotIndex = slotIndex
        self.serialNumber = serialNumber
        self.portIdentifier = portIdentifier
    }
}

extension Array where Element == SlotAssignment {
    /// Upserts an assignment, matching by the set of serial numbers.
    /// If a matching set exists, replaces it; otherwise appends.
    public mutating func upsert(_ new: SlotAssignment) {
        let newSerials = Set(new.entries.map { $0.serialNumber })
        if let index = firstIndex(where: { Set($0.entries.map { $0.serialNumber }) == newSerials }) {
            self[index] = new
        } else {
            append(new)
        }
    }
}

/// A complete saved arrangement for a specific set of monitors.
/// Keyed by MonitorSetSignature so it can be looked up when the same
/// combination of monitor models is detected.
///
/// Contains two kinds of data:
/// - **Arrangement** (slots): the target position and resolution for each slot
/// - **Assignments** (knownAssignments): which physical monitors (by serial/port)
///   have been seen in which slots
/// - **Saved layouts** (savedLayouts): past arrangements, one per combination of
///   display sizes, so switching back to a resolution restores its arrangement
public struct MonitorSetProfile: Hashable, Sendable {
    public var signatureRawValue: String
    public var slots: [MonitorSlotProfile]
    public var knownAssignments: [SlotAssignment]
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var resolutionSignatureRawValue: String?
    public var savedLayouts: [[MonitorSlotProfile]]

    public init(
        signature: MonitorSetSignature,
        slots: [MonitorSlotProfile],
        knownAssignments: [SlotAssignment] = [],
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        resolutionSignature: ResolutionSetSignature? = nil,
        savedLayouts: [[MonitorSlotProfile]] = []
    ) {
        self.signatureRawValue = signature.rawValue
        self.slots = slots
        self.knownAssignments = knownAssignments
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.resolutionSignatureRawValue = resolutionSignature?.rawValue
        self.savedLayouts = savedLayouts
    }

    public var signature: MonitorSetSignature {
        MonitorSetSignature(rawValue: signatureRawValue)
    }

    public var resolutionSignature: ResolutionSetSignature? {
        guard let rawValue = resolutionSignatureRawValue else { return nil }
        return ResolutionSetSignature(rawValue: rawValue)
    }

    /// Returns the saved layout whose display sizes match the live displays, if any.
    public func savedLayout(
        matching pairs: [(display: DisplaySnapshot, slot: MonitorSlotProfile)]
    ) -> [MonitorSlotProfile]? {
        let liveKey = Set(pairs.map {
            Self.sizeKey(
                modelName: $0.slot.modelName,
                slotIndex: $0.slot.slotIndex,
                frameSize: $0.display.frame.size,
                resolution: $0.display.resolution
            )
        })
        return savedLayouts.first { Self.sizeKey(of: $0) == liveKey }
    }

    /// Stores a layout, replacing any saved layout with the same display sizes.
    public mutating func rememberLayout(_ layout: [MonitorSlotProfile]) {
        let key = Self.sizeKey(of: layout)
        savedLayouts.removeAll { Self.sizeKey(of: $0) == key }
        savedLayouts.append(layout)
    }

    private static func sizeKey(of layout: [MonitorSlotProfile]) -> Set<String> {
        Set(layout.map {
            sizeKey(
                modelName: $0.modelName,
                slotIndex: $0.slotIndex,
                frameSize: $0.targetFrame.size,
                resolution: $0.targetResolution
            )
        })
    }

    private static func sizeKey(
        modelName: String,
        slotIndex: Int,
        frameSize: DisplaySize,
        resolution: DisplaySize
    ) -> String {
        "\(modelName)#\(slotIndex):\(frameSize.width)x\(frameSize.height)@\(resolution.width)x\(resolution.height)"
    }
}

// Custom Codable for backward compatibility: old profiles on disk
// don't have knownAssignments or savedLayouts, so we decode them with a fallback to [].
extension MonitorSetProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case signatureRawValue, slots, knownAssignments, updatedAt
        case lastUsedAt, resolutionSignatureRawValue, savedLayouts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatureRawValue = try container.decode(String.self, forKey: .signatureRawValue)
        slots = try container.decode([MonitorSlotProfile].self, forKey: .slots)
        knownAssignments = try container.decodeIfPresent([SlotAssignment].self, forKey: .knownAssignments) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        resolutionSignatureRawValue = try container.decodeIfPresent(String.self, forKey: .resolutionSignatureRawValue)
        savedLayouts = try container.decodeIfPresent([[MonitorSlotProfile]].self, forKey: .savedLayouts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signatureRawValue, forKey: .signatureRawValue)
        try container.encode(slots, forKey: .slots)
        try container.encode(knownAssignments, forKey: .knownAssignments)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(resolutionSignatureRawValue, forKey: .resolutionSignatureRawValue)
        try container.encode(savedLayouts, forKey: .savedLayouts)
    }
}

// MARK: - UI summary

/// Presentation model for the menu bar dropdown. One per connected display,
/// ordered left-to-right by the coordinator.
public struct DisplaySummary: Hashable, Sendable {
    public var modelName: String
    public var resolution: DisplaySize
    public var isBuiltIn: Bool
    public var matchesSaved: Bool

    public init(modelName: String, resolution: DisplaySize, isBuiltIn: Bool, matchesSaved: Bool) {
        self.modelName = modelName
        self.resolution = resolution
        self.isBuiltIn = isBuiltIn
        self.matchesSaved = matchesSaved
    }
}
