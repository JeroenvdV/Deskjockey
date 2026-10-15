import Foundation

/// Pure validation and transformation of complete display targets.
public enum ScreenConfigurationLogic {
    public static func validate(_ displays: [DisplaySnapshot]) throws {
        guard !displays.isEmpty, Set(displays.map(\.runtimeID)).count == displays.count,
              displays.allSatisfy({ !$0.runtimeID.isEmpty && $0.modelID?.isValid == true }),
              displays.filter(\.isMain).count == 1,
              displays.allSatisfy({ !$0.isMirrored && valid($0.frame) && $0.mode.isValid }) else {
            throw DisplaySetError.operationFailed("invalid_observation")
        }
    }

    public static func validate(_ configuration: ScreenConfiguration) throws {
        guard !configuration.slots.isEmpty,
              Set(configuration.slots.map(\.id)).count == configuration.slots.count,
              configuration.slots.allSatisfy({ $0.id >= 0 && $0.modelID.isValid && valid($0.targetFrame)
                  && $0.targetMode.isValid && $0.targetFrame.size == $0.targetMode.logicalSize }),
              let main = configuration.slots.first(where: { $0.id == configuration.mainSlotID }),
              main.targetFrame.origin == DisplayPoint(x: 0, y: 0) else {
            throw DisplaySetError.operationFailed("invalid_configuration")
        }
        let frames = configuration.slots.map(\.targetFrame)
        var neighbors = Array(repeating: Set<Int>(), count: frames.count)
        for i in frames.indices {
            for j in frames.indices where j > i {
                let a = frames[i], b = frames[j]
                let overlapX = min(a.origin.x + a.size.width, b.origin.x + b.size.width) - max(a.origin.x, b.origin.x)
                let overlapY = min(a.origin.y + a.size.height, b.origin.y + b.size.height) - max(a.origin.y, b.origin.y)
                if overlapX > 0 && overlapY > 0 { throw DisplaySetError.operationFailed("overlapping_slots") }
                if overlapX >= 0 && overlapY >= 0 {
                    neighbors[i].insert(j)
                    neighbors[j].insert(i)
                }
            }
        }
        var reached: Set<Int> = [0]
        var pending = [0]
        while let index = pending.popLast() {
            for neighbor in neighbors[index] where reached.insert(neighbor).inserted { pending.append(neighbor) }
        }
        guard reached.count == frames.count else { throw DisplaySetError.operationFailed("disconnected_slots") }
    }

    private static func valid(_ frame: DisplayFrame) -> Bool {
        frame.size.isValid && Int32(exactly: frame.origin.x) != nil && Int32(exactly: frame.origin.y) != nil
    }

    public static func normalized(_ displays: [DisplaySnapshot]) throws -> [DisplaySnapshot] {
        try validate(displays)
        guard let main = displays.first(where: \.isMain) else {
            throw DisplaySetError.operationFailed("missing_main_display")
        }
        return try displays.map { display in
            var result = display
            result.frame.origin.x -= main.frame.origin.x
            result.frame.origin.y -= main.frame.origin.y
            guard valid(result.frame) else { throw DisplaySetError.operationFailed("invalid_relative_geometry") }
            return result
        }
    }

    public static func capture(_ displays: [DisplaySnapshot], mapping: [String: Int]) throws -> ScreenConfiguration {
        let normalized = try normalized(displays)
        guard mapping.count == normalized.count, Set(mapping.values).count == normalized.count else {
            throw DisplaySetError.operationFailed("incomplete_assignment")
        }
        var slots: [DisplaySlot] = []
        var mainSlotID: Int?
        for display in normalized {
            guard let slotID = mapping[display.runtimeID], let modelID = display.modelID else {
                throw DisplaySetError.operationFailed("missing_slot")
            }
            slots.append(DisplaySlot(id: slotID, modelID: modelID,
                                     targetFrame: display.frame, targetMode: display.mode, isBuiltIn: display.isBuiltIn))
            if display.isMain { mainSlotID = slotID }
        }
        guard let mainSlotID else { throw DisplaySetError.operationFailed("missing_main_slot") }
        let configuration = ScreenConfiguration(slots: slots.sorted { $0.id < $1.id }, mainSlotID: mainSlotID)
        try validate(configuration)
        return configuration
    }

    /// Position is evidence only for an edit to an existing configuration, never for a new instance.
    public static func permutation(_ displays: [DisplaySnapshot], of configuration: ScreenConfiguration) throws -> [String: Int]? {
        try validate(configuration)
        let displays = try normalized(displays)
        guard DisplaySetClassID.from(displays) == configuration.classID else { return nil }
        var mapping: [String: Int] = [:]
        var remaining = configuration.slots
        for display in displays.sorted(by: { $0.runtimeID < $1.runtimeID }) {
            let matches = remaining.indices.filter {
                remaining[$0].modelID == display.modelID && remaining[$0].isBuiltIn == display.isBuiltIn
                    && remaining[$0].targetFrame == display.frame
                    && remaining[$0].targetMode == display.mode
                    && (remaining[$0].id == configuration.mainSlotID) == display.isMain
            }
            guard matches.count == 1, let index = matches.first else { return nil }
            mapping[display.runtimeID] = remaining.remove(at: index).id
        }
        return remaining.isEmpty ? mapping : nil
    }

    public static func plan(_ displays: [DisplaySnapshot], configuration: ScreenConfiguration,
                            mapping: [String: Int]) throws -> DisplayApplyPlan {
        try validate(displays)
        try validate(configuration)
        guard DisplaySetClassID.from(displays) == configuration.classID,
              mapping.count == displays.count,
              Set(mapping.values) == Set(configuration.slots.map(\.id)) else {
            throw DisplaySetError.operationFailed("incomplete_assignment")
        }
        let targets = try displays.map { display -> DisplayApplyTarget in
            guard let id = mapping[display.runtimeID],
                  let slot = configuration.slots.first(where: { $0.id == id }), slot.modelID == display.modelID,
                  slot.isBuiltIn == display.isBuiltIn else {
                throw DisplaySetError.operationFailed("incompatible_assignment")
            }
            return DisplayApplyTarget(runtimeID: display.runtimeID, targetFrame: slot.targetFrame,
                                        targetMode: slot.targetMode, isMain: slot.id == configuration.mainSlotID)
        }
        return DisplayApplyPlan(observedDisplays: displays, targets: targets)
    }

    public static func matches(_ displays: [DisplaySnapshot], plan: DisplayApplyPlan) -> Bool {
        guard let normalized = try? normalized(displays),
              Set(displays.map(\.runtimeID)) == Set(plan.observedDisplays.map(\.runtimeID)) else { return false }
        return normalized.allSatisfy { display in
            guard let original = plan.observedDisplays.first(where: { $0.runtimeID == display.runtimeID }),
                  let target = plan.targets.first(where: { $0.runtimeID == display.runtimeID }) else { return false }
            return original.modelID == display.modelID && original.serialNumber == display.serialNumber
                && target.targetFrame == display.frame && target.targetMode == display.mode && target.isMain == display.isMain
        }
    }

    public static func instance(_ displays: [DisplaySnapshot], mapping: [String: Int], now: Date) -> DisplaySetInstance? {
        let devices = displays.compactMap(\.deviceID)
        guard devices.count == displays.count, Set(devices).count == displays.count, !devices.isEmpty else { return nil }
        var assignments: [DisplaySlotAssignment] = []
        for display in displays {
            guard let deviceID = display.deviceID, let slotID = mapping[display.runtimeID] else { return nil }
            assignments.append(DisplaySlotAssignment(deviceID: deviceID, slotID: slotID, logicalUnitNumber: display.logicalUnitNumber))
        }
        return DisplaySetInstance(assignments: assignments.sorted { $0.deviceID < $1.deviceID }, lastUsedAt: now)
    }

    public static func sameConnections(_ lhs: [DisplaySnapshot], _ rhs: [DisplaySnapshot]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.allSatisfy { a in
            rhs.contains { $0.runtimeID == a.runtimeID && $0.modelID == a.modelID
                && $0.serialNumber == a.serialNumber && $0.logicalUnitNumber == a.logicalUnitNumber && $0.isBuiltIn == a.isBuiltIn }
        }
    }
}
