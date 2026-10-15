import Foundation

struct DetectionLog {
    let logger: Logger
    let detectionID = UUID().uuidString

    func debug(_ reason: String, _ fields: [String: String] = [:]) { logger.debug(record(reason, fields)) }
    func info(_ reason: String, _ fields: [String: String] = [:]) { logger.info(record(reason, fields)) }
    func warn(_ reason: String, _ fields: [String: String] = [:]) { logger.warn(record(reason, fields)) }
    func error(_ reason: String, _ fields: [String: String] = [:]) { logger.error(record(reason, fields)) }

    private func record(_ reason: String, _ fields: [String: String]) -> String {
        var values = fields
        values["detection_id"] = detectionID
        values["reason"] = reason
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "reason=log_encoding_failure" }
        return text
    }

    func observe(_ displays: [DisplaySnapshot]) {
        info("observation", ["count": String(displays.count)])
        for display in displays.sorted(by: { $0.runtimeID < $1.runtimeID }) {
            info("display_input", [
                "runtime_id": display.runtimeID, "display_name": display.displayName,
                "model_id": display.modelID?.description ?? "unavailable", "identity_issue": display.identityIssue ?? "none",
                "serial_number": String(display.serialNumber), "logical_unit_number": String(display.logicalUnitNumber),
                "built_in": String(display.isBuiltIn), "main": String(display.isMain), "mirrored": String(display.isMirrored),
                "origin": "\(display.frame.origin.x),\(display.frame.origin.y)",
                "logical_size": "\(display.mode.logicalSize.width)x\(display.mode.logicalSize.height)",
                "pixel_size": "\(display.mode.pixelSize.width)x\(display.mode.pixelSize.height)"
            ])
        }
        for group in Dictionary(grouping: displays, by: { $0.deviceID }).values where group.count > 1 && group[0].deviceID != nil {
            warn("duplicate_serial", ["displays": group.map(\.runtimeID).sorted().joined(separator: ",")])
        }
        if displays.contains(where: { $0.serialNumber == 0 }) { warn("missing_serial") }
    }

    func assignment(_ assignmentResult: SlotAssignmentResult) {
        for id in assignmentResult.mapping.keys.sorted() {
            info(assignmentResult.reasons[id] ?? "assignment", ["runtime_id": id, "slot_id": String(assignmentResult.mapping[id]!)])
        }
    }
}
