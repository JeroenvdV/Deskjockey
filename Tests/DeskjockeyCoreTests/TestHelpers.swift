import Foundation
@testable import DeskjockeyCore

let externalModel = DisplayModelID(vendorID: 0x30ae, productID: 0x61f6)
let laptopModel = DisplayModelID(vendorID: 0x610, productID: 0xa065)

func sampleDisplays(serials: (UInt32, UInt32) = (72, 177)) -> [DisplaySnapshot] {
    let hd = DisplaySize(width: 1920, height: 1080)
    let laptop = DisplaySize(width: 1728, height: 1117)
    return [
        DisplaySnapshot(runtimeID: "1", displayName: "Built-in Retina Display", modelID: laptopModel,
                        serialNumber: 900, isBuiltIn: true,
                        frame: DisplayFrame(origin: .init(x: 0, y: 1080), size: laptop),
                        mode: DisplayMode(logicalSize: laptop, pixelSize: .init(width: 3456, height: 2234))),
        DisplaySnapshot(runtimeID: "5", displayName: "LEN T23i-20 (1)", modelID: externalModel,
                        serialNumber: serials.0, logicalUnitNumber: 3, isMain: true,
                        frame: DisplayFrame(origin: .init(x: 0, y: 0), size: hd),
                        mode: DisplayMode(logicalSize: hd, pixelSize: hd)),
        DisplaySnapshot(runtimeID: "6", displayName: "LEN T23i-20 (2)", modelID: externalModel,
                        serialNumber: serials.1, logicalUnitNumber: 4,
                        frame: DisplayFrame(origin: .init(x: 1920, y: 0), size: hd),
                        mode: DisplayMode(logicalSize: hd, pixelSize: hd))
    ]
}

@MainActor
final class MockDisplayManager: DisplayManaging {
    var displays: [DisplaySnapshot]
    var plans: [DisplayApplyPlan] = []
    var failRead = false
    var failApply = false
    var afterApply: (() -> Void)?
    init(displays: [DisplaySnapshot] = sampleDisplays()) { self.displays = displays }
    func currentDisplays() throws -> [DisplaySnapshot] {
        if failRead { throw DisplaySetError.operationFailed("test_inventory_failure") }
        return displays
    }
    func apply(plan: DisplayApplyPlan) throws {
        if failApply { throw DisplaySetError.operationFailed("test_apply_failure") }
        plans.append(plan)
        for target in plan.targets {
            guard let index = displays.firstIndex(where: { $0.runtimeID == target.runtimeID }) else {
                throw DisplaySetError.displayNotFound(runtimeID: target.runtimeID)
            }
            displays[index].frame = target.targetFrame
            displays[index].mode = target.targetMode
            displays[index].isMain = target.isMain
        }
        afterApply?()
    }
}

final class InMemoryDisplaySetStore: DisplaySetStoring {
    var database = DisplaySetDatabase()
    var failLoad = false
    var failSave = false
    var saves = 0
    func loadDatabase() throws -> DisplaySetDatabase {
        if failLoad { throw DisplaySetError.operationFailed("test_read_failure") }
        return database
    }
    func saveDatabase(_ database: DisplaySetDatabase) throws {
        if failSave { throw DisplaySetError.operationFailed("test_write_failure") }
        try JSONDisplaySetStore.validate(database)
        self.database = database
        saves += 1
    }
}

struct ImmediateSleepManager: SleepManaging {
    func sleep(milliseconds: UInt64) async {}
}

final class RecordingLogger: Logger {
    var lines: [String] = []
    func debug(_ message: String) { lines.append(message) }
    func info(_ message: String) { lines.append(message) }
    func warn(_ message: String) { lines.append(message) }
    func error(_ message: String) { lines.append(message) }
    func contains(_ text: String) -> Bool { lines.contains { $0.contains(text) } }
}

@MainActor
func coordinator(_ manager: MockDisplayManager, _ store: InMemoryDisplaySetStore,
                 logger: Logger = NullLogger()) -> ScreenConfigurationCoordinator {
    ScreenConfigurationCoordinator(displayManager: manager, displaySetStore: store, logger: logger,
                                    sleepManager: ImmediateSleepManager(), reapplyDelayMilliseconds: 0)
}
