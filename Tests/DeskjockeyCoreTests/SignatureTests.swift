import XCTest
@testable import DeskjockeyCore

final class SignatureTests: XCTestCase {
    func testResolutionSetSignatureMatchesSameResolutions() {
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
                modelName: "MacBook Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 1512, height: 982)
            )
        ]

        let setupB = [
            DisplaySnapshot(
                runtimeID: "X",
                modelName: "Some Other Model",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            ),
            DisplaySnapshot(
                runtimeID: "Y",
                modelName: "Another Model",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 1512, height: 982)
            )
        ]

        let sigA = ResolutionSetSignature.from(displays: setupA)
        let sigB = ResolutionSetSignature.from(displays: setupB)
        
        XCTAssertEqual(sigA, sigB)
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
            )
        ]

        let setupB = [
            DisplaySnapshot(
                runtimeID: "A",
                modelName: "Built-in Retina Display",
                isBuiltIn: true,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1512, height: 982)),
                resolution: .init(width: 3024, height: 1964)
            )
        ]

        XCTAssertEqual(
            DisplayTopologyFingerprint.from(displays: setupA),
            DisplayTopologyFingerprint.from(displays: setupB)
        )
    }

    func testResolutionSetSignatureWithDuplicateResolutions() {
        let setup = [
            DisplaySnapshot(
                runtimeID: "A",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            ),
            DisplaySnapshot(
                runtimeID: "B",
                modelName: "Dell U2405",
                isBuiltIn: false,
                frame: .init(origin: .init(x: 1920, y: 0), size: .init(width: 1920, height: 1200)),
                resolution: .init(width: 1920, height: 1200)
            )
        ]

        let sig = ResolutionSetSignature.from(displays: setup)
        
        XCTAssertEqual(sig.rawValue, "1920x1200x2")
    }
}
