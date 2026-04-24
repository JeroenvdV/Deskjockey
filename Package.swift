// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Deskjockey",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DeskjockeyCore",
            targets: ["DeskjockeyCore"]
        ),
        .executable(
            name: "DeskjockeyApp",
            targets: ["DeskjockeyApp"]
        )
    ],
    targets: [
        .target(
            name: "DeskjockeyCore"
        ),
        .executableTarget(
            name: "DeskjockeyApp",
            dependencies: ["DeskjockeyCore"]
        ),
        .testTarget(
            name: "DeskjockeyCoreTests",
            dependencies: ["DeskjockeyCore"]
        )
    ]
)
