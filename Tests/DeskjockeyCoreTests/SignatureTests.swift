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
