// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetalCraftNative",
    platforms: [.macOS(.v13)],
    products: [
        // libmetalcraft_native.dylib — loaded by the MetalCraft Engine mod via JNI
        .library(name: "metalcraft_native", type: .dynamic, targets: ["MetalCraftNative"])
    ],
    targets: [
        .target(
            name: "MetalCraftNative",
            resources: [.process("Shaders")]
        )
    ]
)
