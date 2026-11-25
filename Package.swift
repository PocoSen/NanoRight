// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NanoRight",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NanoRightCore",
            targets: ["NanoRightCore"]
        ),
        .executable(
            name: "NanoRight",
            targets: ["NanoRightApp"]
        )
    ],
    targets: [
        .target(
            name: "NanoRightCore",
            path: "Sources/NanoRightCore"
        ),
        .executableTarget(
            name: "NanoRightApp",
            dependencies: ["NanoRightCore"],
            path: "Sources/NanoRightApp",
            linkerSettings: [
                .linkedFramework("FinderSync")
            ]
        ),
        .testTarget(
            name: "NanoRightCoreTests",
            dependencies: ["NanoRightCore"],
            path: "Tests/NanoRightCoreTests"
        )
    ]
)
