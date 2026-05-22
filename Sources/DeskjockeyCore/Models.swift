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

    public static func normalizeModelName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Display" : trimmed
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
/// Example: "Built-in Retina Displayx1|DELL P3223QEx2"
public struct MonitorSetSignature: Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func from(displays: [DisplaySnapshot]) -> MonitorSetSignature {
        let counts = Dictionary(grouping: displays, by: { $0.normalizedModelName }).mapValues(\.count)
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
            .map { "\($0.normalizedModelName)#\($0.runtimeID)#\($0.isBuiltIn ? "builtIn" : "external")" }
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
public struct MonitorSetProfile: Hashable, Sendable {
    public var signatureRawValue: String
    public var slots: [MonitorSlotProfile]
    public var knownAssignments: [SlotAssignment]
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var resolutionSignatureRawValue: String?

    public init(
        signature: MonitorSetSignature,
        slots: [MonitorSlotProfile],
        knownAssignments: [SlotAssignment] = [],
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        resolutionSignature: ResolutionSetSignature? = nil
    ) {
        self.signatureRawValue = signature.rawValue
        self.slots = slots
        self.knownAssignments = knownAssignments
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.resolutionSignatureRawValue = resolutionSignature?.rawValue
    }

    public var signature: MonitorSetSignature {
        MonitorSetSignature(rawValue: signatureRawValue)
    }

    public var resolutionSignature: ResolutionSetSignature? {
        guard let rawValue = resolutionSignatureRawValue else { return nil }
        return ResolutionSetSignature(rawValue: rawValue)
    }
}

// Custom Codable for backward compatibility: old profiles on disk
// don't have knownAssignments, so we decode it with a fallback to [].
extension MonitorSetProfile: Codable {
    enum CodingKeys: String, CodingKey {
        case signatureRawValue, slots, knownAssignments, updatedAt
        case lastUsedAt, resolutionSignatureRawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatureRawValue = try container.decode(String.self, forKey: .signatureRawValue)
        slots = try container.decode([MonitorSlotProfile].self, forKey: .slots)
        knownAssignments = try container.decodeIfPresent([SlotAssignment].self, forKey: .knownAssignments) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        resolutionSignatureRawValue = try container.decodeIfPresent(String.self, forKey: .resolutionSignatureRawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signatureRawValue, forKey: .signatureRawValue)
        try container.encode(slots, forKey: .slots)
        try container.encode(knownAssignments, forKey: .knownAssignments)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(resolutionSignatureRawValue, forKey: .resolutionSignatureRawValue)
    }
}

// MARK: - Slot resolution

/// Resolves which live display should occupy which slot index.
///
/// Replaces the former position-based SlotPlanner and DisplayMatcher.
/// Position is output of the application and is never used as input for
/// ordering, grouping, or matching. Instead, physical monitors are
/// identified by serial number, with port identifier as a fallback.
///
/// Priority chain within each model-name group:
/// 1. Serial match — known serial → known slot index
/// 2. Elimination — if one unresolved display and one unresolved slot remain
/// 3. Port match — same port identifier → same slot index
/// 4. Alphabetical — serial ascending (nonzero first), then port ascending
public enum SlotResolver {

    /// Resolves slot indices for a set of displays using known assignments.
    /// Returns the resolved pairs and a new assignment record to persist.
    public static func resolve(
        displays: [DisplaySnapshot],
        knownAssignments: [SlotAssignment],
        now: Date = Date()
    ) -> (pairs: [(display: DisplaySnapshot, slotIndex: Int)], assignment: SlotAssignment) {
        let grouped = Dictionary(grouping: displays, by: { $0.normalizedModelName })
        var allPairs: [(display: DisplaySnapshot, slotIndex: Int)] = []
        var allEntries: [SlotAssignmentEntry] = []

        for (modelName, modelDisplays) in grouped {
            let resolved = resolveModelGroup(
                modelName: modelName,
                displays: modelDisplays,
                knownAssignments: knownAssignments
            )
            allPairs.append(contentsOf: resolved)
            allEntries.append(contentsOf: resolved.map { display, slotIndex in
                SlotAssignmentEntry(
                    modelName: modelName,
                    slotIndex: slotIndex,
                    serialNumber: display.serialNumber,
                    portIdentifier: display.portIdentifier
                )
            })
        }

        let assignment = SlotAssignment(entries: allEntries, lastUsedAt: now)
        return (allPairs, assignment)
    }

    /// Convenience: resolves slot indices and pairs with existing profile slots.
    public static func pair(
        liveDisplays: [DisplaySnapshot],
        profileSlots: [MonitorSlotProfile],
        knownAssignments: [SlotAssignment],
        now: Date = Date()
    ) -> (pairs: [(display: DisplaySnapshot, slot: MonitorSlotProfile)], assignment: SlotAssignment) {
        let resolution = resolve(
            displays: liveDisplays,
            knownAssignments: knownAssignments,
            now: now
        )

        let slotsByModelAndIndex = Dictionary(
            grouping: profileSlots,
            by: { "\($0.modelName)#\($0.slotIndex)" }
        )

        let pairs: [(display: DisplaySnapshot, slot: MonitorSlotProfile)] = resolution.pairs.compactMap {
            display, slotIndex in
            let key = "\(display.normalizedModelName)#\(slotIndex)"
            guard let slot = slotsByModelAndIndex[key]?.first else { return nil }
            return (display, slot)
        }

        return (pairs, resolution.assignment)
    }

    // MARK: - Private

    private static func resolveModelGroup(
        modelName: String,
        displays: [DisplaySnapshot],
        knownAssignments: [SlotAssignment]
    ) -> [(display: DisplaySnapshot, slotIndex: Int)] {
        if displays.count == 1 {
            return [(displays[0], 0)]
        }

        // Build lookup tables from all known assignments for this model.
        // Later assignments override earlier ones (more recent data wins).
        var serialToSlot: [UInt32: Int] = [:]
        var portToSlot: [UInt32: Int] = [:]
        for assignment in knownAssignments {
            for entry in assignment.entries where entry.modelName == modelName {
                if entry.serialNumber != 0 {
                    serialToSlot[entry.serialNumber] = entry.slotIndex
                }
                if entry.portIdentifier != 0 {
                    portToSlot[entry.portIdentifier] = entry.slotIndex
                }
            }
        }

        var resolved: [(display: DisplaySnapshot, slotIndex: Int)] = []
        var unresolvedDisplays = displays
        var usedSlotIndices = Set<Int>()

        // Step 1: Serial match
        for display in displays where display.serialNumber != 0 {
            if let slotIndex = serialToSlot[display.serialNumber],
               !usedSlotIndices.contains(slotIndex),
               slotIndex < displays.count {
                resolved.append((display, slotIndex))
                usedSlotIndices.insert(slotIndex)
                unresolvedDisplays.removeAll { $0.runtimeID == display.runtimeID }
            }
        }

        // Step 2: Elimination
        if unresolvedDisplays.count == 1 {
            let remaining = Set(0..<displays.count).subtracting(usedSlotIndices)
            if remaining.count == 1, let slotIndex = remaining.first {
                resolved.append((unresolvedDisplays[0], slotIndex))
                usedSlotIndices.insert(slotIndex)
                unresolvedDisplays.removeAll()
            }
        }

        // Step 3: Port match
        if !unresolvedDisplays.isEmpty {
            var stillUnresolved: [DisplaySnapshot] = []
            for display in unresolvedDisplays {
                if display.portIdentifier != 0,
                   let slotIndex = portToSlot[display.portIdentifier],
                   !usedSlotIndices.contains(slotIndex),
                   slotIndex < displays.count {
                    resolved.append((display, slotIndex))
                    usedSlotIndices.insert(slotIndex)
                } else {
                    stillUnresolved.append(display)
                }
            }
            unresolvedDisplays = stillUnresolved
        }

        // Step 4: Alphabetical fallback
        if !unresolvedDisplays.isEmpty {
            let sorted = unresolvedDisplays.sorted {
                if $0.serialNumber != $1.serialNumber {
                    if $0.serialNumber == 0 { return false }
                    if $1.serialNumber == 0 { return true }
                    return $0.serialNumber < $1.serialNumber
                }
                return $0.portIdentifier < $1.portIdentifier
            }
            let remainingIndices = Set(0..<displays.count).subtracting(usedSlotIndices).sorted()
            for (display, slotIndex) in zip(sorted, remainingIndices) {
                resolved.append((display, slotIndex))
            }
        }

        return resolved
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
