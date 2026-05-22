import Foundation

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
        let grouped = Dictionary(grouping: displays, by: { $0.matchingModelName })
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
            let key = "\(display.matchingModelName)#\(slotIndex)"
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
