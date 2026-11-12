// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KimiUsageBar",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KimiUsageBarCore", targets: ["KimiUsageBarCore"]),
        .executable(name: "KimiUsageBar", targets: ["KimiUsageBar"])
    ],
    targets: [
        .target(name: "KimiUsageBarCore"),
        .executableTarget(
            name: "KimiUsageBar",
            dependencies: ["KimiUsageBarCore"]
        ),
        .testTarget(
            name: "KimiUsageBarCoreTests",
            dependencies: ["KimiUsageBarCore"]
        )
    ]
)
