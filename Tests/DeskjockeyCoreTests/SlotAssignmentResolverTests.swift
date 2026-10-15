import XCTest
@testable import DeskjockeyCore

final class SlotAssignmentResolverTests: XCTestCase {
    private func displaySetClass(_ displays: [DisplaySnapshot]) throws -> DisplaySetClass {
        let mapping = SlotAssignmentResolver.initialSlotAssignments(displays)
        return DisplaySetClass(configuration: try ScreenConfigurationLogic.capture(displays, mapping: mapping))
    }

    func testExactInstanceWinsOverMoreRecentOverlappingHistory() throws {
        let original = sampleDisplays()
        let mapping = SlotAssignmentResolver.initialSlotAssignments(original)
        var saved = try displaySetClass(original)
        saved.record(try XCTUnwrap(ScreenConfigurationLogic.instance(original, mapping: mapping, now: Date(timeIntervalSince1970: 1))))
        var other = sampleDisplays(serials: (72, 999))
        other[1].runtimeID = "15"; other[2].runtimeID = "16"
        var otherMapping = SlotAssignmentResolver.initialSlotAssignments(other)
        let a = otherMapping["15"]!, b = otherMapping["16"]!
        otherMapping["15"] = b; otherMapping["16"] = a
        saved.record(try XCTUnwrap(ScreenConfigurationLogic.instance(other, mapping: otherMapping, now: Date(timeIntervalSince1970: 2))))
        var returned = original
        returned[1].logicalUnitNumber = 4; returned[2].logicalUnitNumber = 3
        let assignmentResult = try SlotAssignmentResolver.resolve(displays: returned, displaySetClass: saved)
        XCTAssertEqual(assignmentResult.mapping, mapping)
        XCTAssertEqual(Set(assignmentResult.reasons.values), ["exact_instance"])
        XCTAssertEqual(saved.instances.count, 2)
    }

    func testPartialDeviceMatchAndEliminationIgnoreCurrentPositions() throws {
        let original = sampleDisplays()
        let mapping = SlotAssignmentResolver.initialSlotAssignments(original)
        var saved = try displaySetClass(original)
        saved.record(try XCTUnwrap(ScreenConfigurationLogic.instance(original, mapping: mapping, now: Date())))
        var partial = sampleDisplays(serials: (72, 999))
        partial[1].frame.origin.x = 4000; partial[2].frame.origin.x = -4000
        let assignmentResult = try SlotAssignmentResolver.resolve(displays: partial, displaySetClass: saved)
        XCTAssertEqual(assignmentResult.mapping, mapping)
        XCTAssertEqual(assignmentResult.reasons["5"], "known_device")
        XCTAssertEqual(assignmentResult.reasons["6"], "elimination")
    }

    func testNewInstanceCanUseLogicalUnitsWithoutPretendingTheyMeanLeft() throws {
        let original = sampleDisplays()
        let mapping = SlotAssignmentResolver.initialSlotAssignments(original)
        var saved = try displaySetClass(original)
        saved.record(try XCTUnwrap(ScreenConfigurationLogic.instance(original, mapping: mapping, now: Date())))
        let replacement = sampleDisplays(serials: (600, 500))
        let assignmentResult = try SlotAssignmentResolver.resolve(displays: replacement, displaySetClass: saved)
        XCTAssertEqual(assignmentResult.mapping, mapping)
        XCTAssertEqual(assignmentResult.reasons["5"], "logical_unit_hint")
        XCTAssertEqual(assignmentResult.reasons["6"], "logical_unit_hint")
    }

    func testMissingAndDuplicateSerialsStillProduceACompleteDeterministicAssignment() throws {
        for serial: UInt32 in [0, 72] {
            var displays = sampleDisplays(serials: (serial, serial))
            displays[1].logicalUnitNumber = 0; displays[2].logicalUnitNumber = 0
            let saved = try displaySetClass(displays)
            let a = try SlotAssignmentResolver.resolve(displays: displays, displaySetClass: saved)
            let b = try SlotAssignmentResolver.resolve(displays: Array(displays.reversed()), displaySetClass: saved)
            XCTAssertEqual(a.mapping, b.mapping)
            XCTAssertEqual(a.mapping.count, displays.count)
            XCTAssertEqual(Set(a.mapping.values).count, displays.count)
            XCTAssertNil(ScreenConfigurationLogic.instance(displays, mapping: a.mapping, now: Date()))
            _ = try ScreenConfigurationLogic.plan(displays, configuration: saved.configuration, mapping: a.mapping)
        }
    }

    func testSerialIdentityIncludesModel() throws {
        var displays = sampleDisplays(serials: (72, 72))
        displays[2].modelID = DisplayModelID(vendorID: 10, productID: 20)
        let instance = ScreenConfigurationLogic.instance(displays, mapping: SlotAssignmentResolver.initialSlotAssignments(displays), now: Date())
        XCTAssertNotNil(instance)
        XCTAssertEqual(instance?.devices.count, 3)
    }

    func testMalformedExactInstanceDoesNotProduceAPartialPlan() throws {
        let displays = sampleDisplays()
        let mapping = SlotAssignmentResolver.initialSlotAssignments(displays)
        var saved = try displaySetClass(displays)
        var instance = try XCTUnwrap(ScreenConfigurationLogic.instance(displays, mapping: mapping, now: Date()))
        instance.assignments[1].slotID = instance.assignments[0].slotID
        saved.instances = [instance]
        XCTAssertThrowsError(try SlotAssignmentResolver.resolve(displays: displays, displaySetClass: saved))
    }
}
