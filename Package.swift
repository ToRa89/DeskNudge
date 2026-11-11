// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "DeskNudge",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "DeskCore"),
        .executableTarget(name: "DeskNudge", dependencies: ["DeskCore"]),
        .testTarget(name: "DeskCoreTests", dependencies: ["DeskCore"]),
    ],
    swiftLanguageModes: [.v5]
)
