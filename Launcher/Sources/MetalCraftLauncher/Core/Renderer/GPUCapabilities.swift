import Foundation
import Metal

/// Hardware detection: Apple Silicon vs Intel, GPU capabilities, memory.
/// Drives renderer-mode availability and optimization recommendations.
struct HardwareReport {
    let isAppleSilicon: Bool
    let cpuName: String
    let physicalMemoryMB: Int
    let performanceCores: Int
    let gpuName: String
    let hasUnifiedMemory: Bool
    let supportsMetal3: Bool
    let recommendedGPUWorkingSetMB: Int
    let macOSVersion: OperatingSystemVersion

    static func current() -> HardwareReport {
        let device = MTLCreateSystemDefaultDevice()

        var isARM = false
        var size = MemoryLayout<Int32>.size
        var value: Int32 = 0
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 {
            isARM = value == 1
        }

        var cpuBrand = [CChar](repeating: 0, count: 256)
        var brandSize = cpuBrand.count
        sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &brandSize, nil, 0)

        var perfCores: Int32 = 0
        var pcSize = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &perfCores, &pcSize, nil, 0) != 0 {
            var all: Int32 = 0
            var allSize = MemoryLayout<Int32>.size
            sysctlbyname("hw.physicalcpu", &all, &allSize, nil, 0)
            perfCores = all
        }

        return HardwareReport(
            isAppleSilicon: isARM,
            cpuName: String(cString: cpuBrand),
            physicalMemoryMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
            performanceCores: Int(perfCores),
            gpuName: device?.name ?? "Unknown GPU",
            hasUnifiedMemory: device?.hasUnifiedMemory ?? false,
            supportsMetal3: device?.supportsFamily(.metal3) ?? false,
            recommendedGPUWorkingSetMB: Int((device?.recommendedMaxWorkingSetSize ?? 0) / 1_048_576),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersion
        )
    }

    /// Compatibility gate for the Experimental Metal Renderer.
    var supportsExperimentalMetal: Bool {
        supportsMetal3 && macOSVersion.majorVersion >= 13
    }
}
