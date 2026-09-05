// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TargetEco",
    platforms: [
        .iOS(.v18),
        .visionOS(.v2),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "TargetCore",
            targets: ["TargetCore"]
        ),
        .library(
            name: "TargetStudioAVP",
            targets: ["TargetStudioAVP"]
        ),
        .library(
            name: "TargetScannerFree",
            targets: ["TargetScannerFree"]
        ),
    ],
    targets: [
        .target(
            name: "TargetCore",
            dependencies: [],
            path: "Sources/TargetCore"
        ),
        .target(
            name: "TargetStudioAVP",
            dependencies: ["TargetCore"],
            path: "Sources/TargetStudioAVP"
        ),
        .target(
            name: "TargetScannerFree",
            dependencies: ["TargetCore"],
            path: "Sources/TargetScannerFree"
        ),
        .testTarget(
            name: "TargetCoreTests",
            dependencies: ["TargetCore"],
            path: "Tests/TargetCoreTests"
        ),
    ]
)
