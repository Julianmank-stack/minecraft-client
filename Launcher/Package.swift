// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetalCraftLauncher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MetalCraftLauncher",
            path: "Sources/MetalCraftLauncher"
        ),
        .testTarget(
            name: "MetalCraftLauncherTests",
            dependencies: ["MetalCraftLauncher"],
            path: "Tests/MetalCraftLauncherTests"
        )
    ]
)
