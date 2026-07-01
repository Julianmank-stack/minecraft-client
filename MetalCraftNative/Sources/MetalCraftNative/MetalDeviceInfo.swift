import Foundation
import Metal

/// GPU capability queries used by both the Java bridge and the terrain renderer.
final class MetalDeviceInfo {
    static let shared = MetalDeviceInfo()

    let device: MTLDevice?

    private init() {
        device = MTLCreateSystemDefaultDevice()
    }

    var name: String { device?.name ?? "No Metal device" }

    var hasUnifiedMemory: Bool { device?.hasUnifiedMemory ?? false }

    var supportsMetal3: Bool { device?.supportsFamily(.metal3) ?? false }

    var recommendedWorkingSetMB: Int64 {
        Int64((device?.recommendedMaxWorkingSetSize ?? 0) / 1_048_576)
    }
}
