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

    /// Used by DisplayMatcher to find the nearest saved slot for a live display.
    var center: (x: Double, y: Double) {
        let centerX = Double(origin.x) + (Double(size.width) / 2.0)
        let centerY = Double(origin.y) + (Double(size.height) / 2.0)
        return (centerX, centerY)
    }
}

// MARK: - Display snapshot

/// A point-in-time capture of a single display's state as seen by the OS.
/// The runtimeID is a CGDirectDisplayID (as String) -- it can change between
/// reboots or when cables are swapped, so we never use it for profile matching.
public struct DisplaySnapshot: Codable, Hashable, Sendable {
    public var runtimeID: String
    public var modelName: String
    public var isBuiltIn: Bool
    public var frame: DisplayFrame
    public var resolution: DisplaySize

    public init(
        runtimeID: String,
        modelName: String,
        isBuiltIn: Bool,
        frame: DisplayFrame,
        resolution: DisplaySize
    ) {
        self.runtimeID = runtimeID
        self.modelName = modelName
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

/// A complete saved arrangement for a specific set of monitors.
/// Keyed by MonitorSetSignature so it can be looked up when the same
/// combination of monitor models is detected.
public struct MonitorSetProfile: Codable, Hashable, Sendable {
    public var signatureRawValue: String
    public var slots: [MonitorSlotProfile]
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var resolutionSignatureRawValue: String?

    public init(
        signature: MonitorSetSignature,
        slots: [MonitorSlotProfile],
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        resolutionSignature: ResolutionSetSignature? = nil
    ) {
        self.signatureRawValue = signature.rawValue
        self.slots = slots
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

// MARK: - Slot planning

public enum SlotPlanner {
    /// Assigns deterministic slot indexes to displays of the same model by their
    /// physical position (left-to-right, top-to-bottom). This ensures that two
    /// identical monitors get consistent slot numbers regardless of which port
    /// or cable they're connected to.
    public static func indexedSlots(
        for displays: [DisplaySnapshot]
    ) -> [String: [IndexedDisplay]] {
        let grouped = Dictionary(grouping: displays, by: { $0.normalizedModelName })
        var result: [String: [IndexedDisplay]] = [:]

        for (modelName, modelDisplays) in grouped {
            let sorted = modelDisplays.sortedByPosition()
            result[modelName] = sorted.enumerated().map { index, display in
                IndexedDisplay(slotIndex: index, display: display)
            }
        }
        return result
    }
}

public struct IndexedDisplay: Hashable, Sendable {
    public var slotIndex: Int
    public var display: DisplaySnapshot

    public init(slotIndex: Int, display: DisplaySnapshot) {
        self.slotIndex = slotIndex
        self.display = display
    }
}

// MARK: - Display matching

public enum DisplayMatcher {
    /// Pairs saved profile slots with currently connected displays of the same model.
    /// Uses nearest-center-point matching so that if two identical monitors are present,
    /// each gets matched to the slot whose saved position is closest to its current
    /// position. This handles the case where runtime IDs changed (different desk/dock)
    /// but the physical layout is similar.
    public static func pair(
        liveDisplays: [DisplaySnapshot],
        profileSlots: [MonitorSlotProfile]
    ) -> [(display: DisplaySnapshot, slot: MonitorSlotProfile)] {
        let displaysByModel = Dictionary(grouping: liveDisplays, by: \.normalizedModelName)
        let slotsByModel = Dictionary(grouping: profileSlots, by: \.modelName)
        var result: [(display: DisplaySnapshot, slot: MonitorSlotProfile)] = []

        for (modelName, slots) in slotsByModel {
            var unmatchedDisplays = (displaysByModel[modelName] ?? []).sortedByPosition()
            let sortedSlots = slots.sorted(by: { $0.slotIndex < $1.slotIndex })

            for slot in sortedSlots {
                guard !unmatchedDisplays.isEmpty else { break }
                let nearestIndex = unmatchedDisplays
                    .enumerated()
                    .min { lhs, rhs in
                        let leftDistance = squaredDistance(from: lhs.element.frame, to: slot.targetFrame)
                        let rightDistance = squaredDistance(from: rhs.element.frame, to: slot.targetFrame)
                        if leftDistance != rightDistance {
                            return leftDistance < rightDistance
                        }
                        return lhs.element.runtimeID < rhs.element.runtimeID
                    }?
                    .offset ?? 0
                let display = unmatchedDisplays.remove(at: nearestIndex)
                result.append((display: display, slot: slot))
            }
        }

        return result
    }

    /// Squared Euclidean distance between frame centers. No sqrt needed since
    /// we only compare relative distances, not absolute values.
    private static func squaredDistance(from lhs: DisplayFrame, to rhs: DisplayFrame) -> Double {
        let lhsCenter = lhs.center
        let rhsCenter = rhs.center
        let dx = lhsCenter.x - rhsCenter.x
        let dy = lhsCenter.y - rhsCenter.y
        return (dx * dx) + (dy * dy)
    }
}

// MARK: - Sorting helpers

/// Sorting extension for DisplaySnapshot arrays to ensure consistent ordering
/// across the codebase. Displays are sorted left-to-right, then top-to-bottom,
/// with runtime ID as a final tiebreaker for deterministic ordering.
extension Array where Element == DisplaySnapshot {
    /// Sorts displays by their physical position (left-to-right, top-to-bottom).
    /// Used consistently throughout the app for display ordering in menus and matching.
    public func sortedByPosition() -> [DisplaySnapshot] {
        self.sorted {
            if $0.frame.origin.x != $1.frame.origin.x {
                return $0.frame.origin.x < $1.frame.origin.x
            }
            if $0.frame.origin.y != $1.frame.origin.y {
                return $0.frame.origin.y < $1.frame.origin.y
            }
            return $0.runtimeID < $1.runtimeID
        }
    }
}

/// Sorting extension for MonitorSlotProfile arrays to ensure consistent ordering
/// across the codebase. Slots are sorted by their target frame position (left-to-right, top-to-bottom).
extension Array where Element == MonitorSlotProfile {
    /// Sorts slot profiles by their target frame position (left-to-right, top-to-bottom).
    /// Used for consistent slot ordering when copying profiles between similar setups.
    public func sortedByPosition() -> [MonitorSlotProfile] {
        self.sorted {
            if $0.targetFrame.origin.x != $1.targetFrame.origin.x {
                return $0.targetFrame.origin.x < $1.targetFrame.origin.x
            }
            return $0.targetFrame.origin.y < $1.targetFrame.origin.y
        }
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
