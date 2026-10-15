import XCTest
@testable import DeskjockeyCore

final class DisplaySetIdentityTests: XCTestCase {
    func testClassIgnoresNamesSerialsConnectionOrderAndSettings() {
        let original = sampleDisplays()
        var changed = Array(original.reversed())
        for index in changed.indices {
            changed[index].displayName = "An entirely different label (99)"
            changed[index].serialNumber += 1
            changed[index].runtimeID += "new"
            changed[index].logicalUnitNumber += 5
            changed[index].frame.origin.x += 50
            changed[index].mode.pixelSize.width += 100
        }
        XCTAssertEqual(DisplaySetClassID.from(original), DisplaySetClassID.from(changed))
        XCTAssertEqual(original[1].displayName, "LEN T23i-20 (1)")
    }

    func testVendorModelCountsAndBuiltInModelDefineClass() {
        let original = sampleDisplays()
        var changed = original
        changed[1].modelID = DisplayModelID(vendorID: 22, productID: externalModel.productID)
        XCTAssertNotEqual(DisplaySetClassID.from(original), DisplaySetClassID.from(changed))
        changed = original
        changed[0].modelID = DisplayModelID(vendorID: laptopModel.vendorID, productID: 123)
        XCTAssertNotEqual(DisplaySetClassID.from(original), DisplaySetClassID.from(changed))
        XCTAssertNotEqual(DisplaySetClassID.from(original), DisplaySetClassID.from(Array(original.dropLast())))
    }

    func testUnavailableIdentityCannotBecomeAClass() {
        var displays = sampleDisplays()
        displays[1].modelID = nil
        XCTAssertNil(DisplaySetClassID.from(displays))
        XCTAssertThrowsError(try ScreenConfigurationLogic.validate(displays))
        displays[1].modelID = DisplayModelID(vendorID: 0, productID: 1)
        XCTAssertNil(DisplaySetClassID.from(displays))
    }

    func testInvalidSavedGeometryAndModesAreRejectedBeforeApplication() throws {
        let displays = sampleDisplays()
        let configuration = try ScreenConfigurationLogic.capture(displays, mapping: SlotAssignmentResolver.initialSlotAssignments(displays))
        var overlapping = configuration
        overlapping.slots[2].targetFrame.origin = overlapping.slots[1].targetFrame.origin
        var disconnected = configuration
        disconnected.slots[2].targetFrame.origin.x = 9000
        var inconsistentMode = configuration
        inconsistentMode.slots[0].targetMode.logicalSize.width += 100
        for invalid in [overlapping, disconnected, inconsistentMode] {
            XCTAssertThrowsError(try ScreenConfigurationLogic.validate(invalid))
            XCTAssertThrowsError(try ScreenConfigurationLogic.plan(displays, configuration: invalid,
                                                            mapping: SlotAssignmentResolver.initialSlotAssignments(displays)))
        }
    }

    func testCaptureUsesRelativeGeometryAndAnExplicitMainSlot() throws {
        var displays = sampleDisplays()
        for i in displays.indices { displays[i].frame.origin.x += 800; displays[i].frame.origin.y -= 200 }
        let mapping = SlotAssignmentResolver.initialSlotAssignments(displays)
        let configuration = try ScreenConfigurationLogic.capture(displays, mapping: mapping)
        XCTAssertEqual(configuration.mainSlotID, mapping["5"])
        XCTAssertEqual(configuration.slots.first { $0.id == configuration.mainSlotID }?.targetFrame.origin, .init(x: 0, y: 0))
        let laptop = try XCTUnwrap(configuration.slots.first { $0.modelID == laptopModel })
        XCTAssertNotEqual(laptop.targetMode.logicalSize, laptop.targetMode.pixelSize)
        XCTAssertEqual(laptop.targetFrame.origin, .init(x: 0, y: 1080))
    }
}
