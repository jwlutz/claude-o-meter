// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeoMeter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "claude-o-meter", targets: ["ClaudeoMeterApp"]),
        .library(name: "ClaudeoMeterCore", targets: ["ClaudeoMeterCore"]),
    ],
    targets: [
        .target(name: "ClaudeoMeterCore"),
        .executableTarget(
            name: "ClaudeoMeterApp",
            dependencies: ["ClaudeoMeterCore"]
        ),
    ]
)
