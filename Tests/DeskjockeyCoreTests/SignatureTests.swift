import XCTest
@testable import DeskjockeyCore

final class SignatureTests: XCTestCase {
    func testSignatureIgnoresPortOrderAndRuntimeIDs() {
        let setupA = [
            DisplaySnapshot(
                runtimeID: "A",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            ),
            DisplaySnapshot(
                runtimeID: "B",
                modelName: "Built-in Retina Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 1512, height: 982)
            )
        ]

        let setupB = [
            DisplaySnapshot(
                runtimeID: "X",
                modelName: "Built-in Retina Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 1512, height: 982)
            ),
            DisplaySnapshot(
                runtimeID: "Y",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            )
        ]

        XCTAssertEqual(
            MonitorSetSignature.from(displays: setupA),
            MonitorSetSignature.from(displays: setupB)
        )
    }

    func testSignatureCollapsesBuiltInDisplayNameVariants() {
        let setupA = [
            DisplaySnapshot(
                runtimeID: "A",
                modelName: "Built-in Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 3024, height: 1964)
            ),
            DisplaySnapshot(
                runtimeID: "B",
                modelName: "DELL P3225QE",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 1512, y: 0), size: .init(width: 3840, height: 2160)),
                resolution: .init(width: 3840, height: 2160)
            )
        ]

        let setupB = [
            DisplaySnapshot(
                runtimeID: "A",
                modelName: "Built-in Retina Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 3024, height: 1964)
            ),
            DisplaySnapshot(
                runtimeID: "B",
                modelName: "DELL P3225QE",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 1512, y: 0), size: .init(width: 3840, height: 2160)),
                resolution: .init(width: 3840, height: 2160)
            )
        ]

        XCTAssertEqual(
            MonitorSetSignature.from(displays: setupA),
            MonitorSetSignature.from(displays: setupB)
        )
        // The persisted signature format is intentionally compact: `ModelxCount|ModelxCount`.
        XCTAssertEqual(
            MonitorSetSignature.from(displays: setupA).rawValue,
            "Built-in Displayx1|DELL P3225QEx1"
        )
    }

    func testTopologyFingerprintCollapsesBuiltInDisplayNameVariants() {
        let setupA = [
            DisplaySnapshot(
                runtimeID: "A",
                modelName: "Built-in Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 3024, height: 1964)
            ),
            DisplaySnapshot(
                runtimeID: "B",
                modelName: "DELL P3225QE",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 1512, y: 0), size: .init(width: 3840, height: 2160)),
                resolution: .init(width: 3840, height: 2160)
            )
        ]

        let setupB = [
            DisplaySnapshot(
                runtimeID: "A",
                modelName: "Built-in Retina Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 3024, height: 1964)
            ),
            DisplaySnapshot(
                runtimeID: "B",
                modelName: "DELL P3225QE",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 1512, y: 0), size: .init(width: 3840, height: 2160)),
                resolution: .init(width: 3840, height: 2160)
            )
        ]

        XCTAssertEqual(
            DisplayTopologyFingerprint.from(displays: setupA),
            DisplayTopologyFingerprint.from(displays: setupB)
        )
    }
}
