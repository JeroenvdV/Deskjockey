import Foundation

public struct SlotAssignmentResult {
    public var mapping: [String: Int]
    public var reasons: [String: String]
}

/// Resolves model-compatible slots without using current screen positions.
public enum SlotAssignmentResolver {
    public static func resolve(displays: [DisplaySnapshot], displaySetClass: DisplaySetClass,
                               session: [String: Int]? = nil) throws -> SlotAssignmentResult {
        try ScreenConfigurationLogic.validate(displays)
        try ScreenConfigurationLogic.validate(displaySetClass.configuration)
        guard DisplaySetClassID.from(displays) == displaySetClass.classID else {
            throw DisplaySetError.operationFailed("class_mismatch")
        }
        let devices = displays.compactMap(\.deviceID)
        if devices.count == displays.count && Set(devices).count == displays.count {
            let exact = displaySetClass.instances.filter { $0.devices == devices.sorted() }
            guard exact.count <= 1 else { throw DisplaySetError.operationFailed("conflicting_exact_instances") }
            if let instance = exact.first {
                var mapping: [String: Int] = [:]
                for display in displays {
                    let matches = instance.assignments.filter { $0.deviceID == display.deviceID }
                    guard matches.count == 1, let assignment = matches.first else {
                        throw DisplaySetError.operationFailed("invalid_instance_assignment")
                    }
                    mapping[display.runtimeID] = assignment.slotID
                }
                _ = try ScreenConfigurationLogic.plan(displays, configuration: displaySetClass.configuration, mapping: mapping)
                return SlotAssignmentResult(mapping: mapping, reasons: mapping.mapValues { _ in "exact_instance" })
            }
        }
        if let session, (try? ScreenConfigurationLogic.plan(displays, configuration: displaySetClass.configuration, mapping: session)) != nil {
            return SlotAssignmentResult(mapping: session, reasons: session.mapValues { _ in "session_assignment" })
        }
        var result = SlotAssignmentResult(mapping: [:], reasons: [:])
        let history = displaySetClass.instances.sorted { $0.lastUsedAt > $1.lastUsedAt }
        let groups = Dictionary(grouping: displays, by: { $0.modelID! })
        for model in groups.keys.sorted() {
            var remaining = (groups[model] ?? []).sorted(by: precedes)
            var slots = displaySetClass.configuration.slots.filter { $0.modelID == model }.map(\.id).sorted()
            let counts = Dictionary(grouping: remaining, by: \.serialNumber).mapValues(\.count)
            func assign(_ display: DisplaySnapshot, _ slot: Int, _ reason: String) {
                result.mapping[display.runtimeID] = slot
                result.reasons[display.runtimeID] = reason
                remaining.removeAll { $0.runtimeID == display.runtimeID }
                slots.removeAll { $0 == slot }
            }
            for display in remaining {
                guard counts[display.serialNumber] == 1, let device = display.deviceID else { continue }
                if let known = history.lazy.flatMap({ $0.assignments }).first(where: {
                    $0.deviceID == device && slots.contains($0.slotID)
                }) { assign(display, known.slotID, "known_device") }
            }
            if remaining.count == 1, let display = remaining.first, let slot = slots.first {
                assign(display, slot, "elimination")
            }
            for display in remaining where display.logicalUnitNumber != 0 {
                if let known = history.lazy.flatMap({ $0.assignments }).first(where: {
                    $0.deviceID.modelID == model && $0.logicalUnitNumber == display.logicalUnitNumber && slots.contains($0.slotID)
                }) { assign(display, known.slotID, "logical_unit_hint") }
            }
            for (display, slot) in zip(remaining, slots) {
                result.mapping[display.runtimeID] = slot
                result.reasons[display.runtimeID] = "ordered_fallback"
            }
        }
        _ = try ScreenConfigurationLogic.plan(displays, configuration: displaySetClass.configuration, mapping: result.mapping)
        return result
    }

    public static func initialSlotAssignments(_ displays: [DisplaySnapshot]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: displays.sorted(by: precedes).enumerated().map { ($0.element.runtimeID, $0.offset) })
    }

    private static func precedes(_ lhs: DisplaySnapshot, _ rhs: DisplaySnapshot) -> Bool {
        if lhs.modelID != rhs.modelID {
            guard let left = lhs.modelID else { return false }
            guard let right = rhs.modelID else { return true }
            return left < right
        }
        if lhs.serialNumber != rhs.serialNumber {
            if lhs.serialNumber == 0 { return false }
            if rhs.serialNumber == 0 { return true }
            return lhs.serialNumber < rhs.serialNumber
        }
        if lhs.logicalUnitNumber != rhs.logicalUnitNumber { return lhs.logicalUnitNumber < rhs.logicalUnitNumber }
        return lhs.runtimeID < rhs.runtimeID
    }
}
