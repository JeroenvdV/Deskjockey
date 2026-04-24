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
}
