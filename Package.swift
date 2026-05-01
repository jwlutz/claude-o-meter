// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeMeter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "claudometer", targets: ["ClaudeMeterApp"]),
        .library(name: "ClaudeMeterCore", targets: ["ClaudeMeterCore"]),
    ],
    targets: [
        .target(name: "ClaudeMeterCore"),
        .executableTarget(
            name: "ClaudeMeterApp",
            dependencies: ["ClaudeMeterCore"]
        ),
    ]
)
