import Foundation

public struct DisplayPoint: Codable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public struct DisplaySize: Codable, Hashable, Sendable, Comparable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public var isValid: Bool { width > 0 && height > 0 && width <= 65536 && height <= 65536 }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.width == rhs.width ? lhs.height < rhs.height : lhs.width < rhs.width
    }
}

public struct DisplayFrame: Codable, Hashable, Sendable {
    public var origin: DisplayPoint
    public var size: DisplaySize
    public init(origin: DisplayPoint, size: DisplaySize) { self.origin = origin; self.size = size }
}

public struct DisplayModelID: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let vendorID: UInt32
    public let productID: UInt32
    public init(vendorID: UInt32, productID: UInt32) { self.vendorID = vendorID; self.productID = productID }
    public var isValid: Bool { vendorID != 0 && productID != 0 }
    public var description: String { "\(String(vendorID, radix: 16)):\(String(productID, radix: 16))" }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.vendorID == rhs.vendorID ? lhs.productID < rhs.productID : lhs.vendorID < rhs.vendorID
    }
}

public struct DisplayMode: Codable, Hashable, Sendable {
    public var logicalSize: DisplaySize
    public var pixelSize: DisplaySize
    public init(logicalSize: DisplaySize, pixelSize: DisplaySize) {
        self.logicalSize = logicalSize; self.pixelSize = pixelSize
    }
    public var isValid: Bool { logicalSize.isValid && pixelSize.isValid }
}

public struct DisplaySnapshot: Hashable, Sendable {
    public var runtimeID: String
    public var displayName: String
    public var modelID: DisplayModelID?
    public var serialNumber: UInt32
    public var logicalUnitNumber: UInt32
    public var isBuiltIn: Bool
    public var isMain: Bool
    public var isMirrored: Bool
    public var frame: DisplayFrame
    public var mode: DisplayMode
    public var identityIssue: String?
    public init(runtimeID: String, displayName: String, modelID: DisplayModelID?, serialNumber: UInt32 = 0,
                logicalUnitNumber: UInt32 = 0, isBuiltIn: Bool = false, isMain: Bool = false,
                isMirrored: Bool = false, frame: DisplayFrame, mode: DisplayMode, identityIssue: String? = nil) {
        self.runtimeID = runtimeID; self.displayName = displayName; self.modelID = modelID
        self.serialNumber = serialNumber; self.logicalUnitNumber = logicalUnitNumber
        self.isBuiltIn = isBuiltIn; self.isMain = isMain; self.isMirrored = isMirrored
        self.frame = frame; self.mode = mode; self.identityIssue = identityIssue
    }
    public var deviceID: DisplayDeviceID? {
        guard let modelID, modelID.isValid, serialNumber != 0 else { return nil }
        return DisplayDeviceID(modelID: modelID, serialNumber: serialNumber)
    }
}

public struct DisplayDeviceID: Codable, Hashable, Sendable, Comparable {
    public let modelID: DisplayModelID
    public let serialNumber: UInt32
    public init(modelID: DisplayModelID, serialNumber: UInt32) {
        self.modelID = modelID; self.serialNumber = serialNumber
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.modelID == rhs.modelID ? lhs.serialNumber < rhs.serialNumber : lhs.modelID < rhs.modelID
    }
}

/// Sorted identities retain multiplicity. Names and device serials are not class identity.
public struct DisplaySetClassID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let models: [DisplayModelID]
    public init(models: [DisplayModelID]) { self.models = models.sorted() }
    public var description: String { models.map(\.description).joined(separator: "|") }
    public static func from(_ displays: [DisplaySnapshot]) -> Self? {
        let models = displays.compactMap(\.modelID)
        guard !displays.isEmpty, models.count == displays.count, models.allSatisfy(\.isValid) else { return nil }
        return Self(models: models)
    }
}

public struct DisplaySlot: Codable, Hashable, Sendable {
    public let id: Int
    public let modelID: DisplayModelID
    public var isBuiltIn: Bool
    public var targetFrame: DisplayFrame
    public var targetMode: DisplayMode
    public init(id: Int, modelID: DisplayModelID, targetFrame: DisplayFrame, targetMode: DisplayMode,
                isBuiltIn: Bool = false) {
        self.id = id; self.modelID = modelID; self.isBuiltIn = isBuiltIn
        self.targetFrame = targetFrame; self.targetMode = targetMode
    }
}

public struct ScreenConfiguration: Codable, Hashable, Sendable {
    public var slots: [DisplaySlot]
    public var mainSlotID: Int
    public init(slots: [DisplaySlot], mainSlotID: Int) { self.slots = slots; self.mainSlotID = mainSlotID }
    public var classID: DisplaySetClassID { DisplaySetClassID(models: slots.map(\.modelID)) }
}

public struct DisplaySlotAssignment: Codable, Hashable, Sendable {
    public let deviceID: DisplayDeviceID
    public var slotID: Int
    public var logicalUnitNumber: UInt32
    public init(deviceID: DisplayDeviceID, slotID: Int, logicalUnitNumber: UInt32) {
        self.deviceID = deviceID; self.slotID = slotID; self.logicalUnitNumber = logicalUnitNumber
    }
}

public struct DisplaySetInstance: Codable, Hashable, Sendable {
    public var assignments: [DisplaySlotAssignment]
    public var lastUsedAt: Date
    public init(assignments: [DisplaySlotAssignment], lastUsedAt: Date) {
        self.assignments = assignments; self.lastUsedAt = lastUsedAt
    }
    public var devices: [DisplayDeviceID] { assignments.map(\.deviceID).sorted() }
}

public struct DisplaySetClass: Codable, Hashable, Sendable {
    public var configuration: ScreenConfiguration
    public var instances: [DisplaySetInstance]
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public init(configuration: ScreenConfiguration, instances: [DisplaySetInstance] = [],
                updatedAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.configuration = configuration; self.instances = instances
        self.updatedAt = updatedAt; self.lastUsedAt = lastUsedAt
    }
    public var classID: DisplaySetClassID { configuration.classID }
    public mutating func record(_ instance: DisplaySetInstance) {
        instances.removeAll { $0.devices == instance.devices }
        instances.append(instance)
        lastUsedAt = instance.lastUsedAt
    }
}

public struct DisplayApplyTarget: Codable, Hashable, Sendable {
    public let runtimeID: String
    public let targetFrame: DisplayFrame
    public let targetMode: DisplayMode
    public let isMain: Bool
    public init(runtimeID: String, targetFrame: DisplayFrame, targetMode: DisplayMode, isMain: Bool) {
        self.runtimeID = runtimeID; self.targetFrame = targetFrame; self.targetMode = targetMode; self.isMain = isMain
    }
}

public struct DisplayApplyPlan: Sendable {
    public let observedDisplays: [DisplaySnapshot]
    public let targets: [DisplayApplyTarget]
    public init(observedDisplays: [DisplaySnapshot], targets: [DisplayApplyTarget]) {
        self.observedDisplays = observedDisplays; self.targets = targets
    }
}

public struct DisplaySummary: Sendable {
    public let displayName: String
    public let pixelSize: DisplaySize
    public let isBuiltIn: Bool
    public let matchesScreenConfiguration: Bool
}

public struct DisplaySwapCandidate: Hashable, Sendable {
    public let firstRuntimeID: String
    public let secondRuntimeID: String
    public let title: String
}

public struct DisplaySetState: Sendable {
    public var summaries: [DisplaySummary] = []
    public var hasSavedScreenConfiguration = false
    public var matchesScreenConfiguration = false
    public var swapCandidates: [DisplaySwapCandidate] = []
    public var lastProcessedAt: Date?
    public init() {}
}
