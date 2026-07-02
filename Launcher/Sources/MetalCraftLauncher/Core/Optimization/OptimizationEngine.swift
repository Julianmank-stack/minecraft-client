import Foundation

/// Turns performance presets + hardware into concrete JVM arguments, RAM
/// allocations, renderer recommendations and engine config.
/// See docs/FPS_OPTIMIZATION.md for the full rule table.
final class OptimizationEngine {
    let hardware: HardwareReport

    init(hardware: HardwareReport) {
        self.hardware = hardware
    }

    // MARK: - Recommendations

    func recommendedProfile() -> PerformanceProfile {
        if hardware.isAppleSilicon && hardware.supportsMetal3 {
            return hardware.physicalMemoryMB >= 16_384 ? .maxFPS : .balanced
        }
        if hardware.physicalMemoryMB < 8_192 { return .lowEnd }
        return .balanced
    }

    func recommendedRAM(for profile: PerformanceProfile) -> Int {
        let physical = hardware.physicalMemoryMB
        switch profile {
        case .balanced: return min(physical / 4, 4096)
        case .maxFPS: return min(physical / 3, 8192)
        case .lowEnd: return 2048
        case .shaderFriendly: return min(physical / 3, 6144)
        case .safe: return 2048
        }
    }

    /// Estimated FPS improvement ranges, by hardware class. Always presented in
    /// the UI as *estimates* — replaced by measured numbers once a benchmark runs.
    func estimatedImprovement(for mode: RendererMode) -> ClosedRange<Int>? {
        switch mode {
        case .standardGL, .safe: return nil
        case .macOptimizedGL: return 10...25
        case .appleSiliconMax: return hardware.isAppleSilicon ? 20...45 : nil
        case .lowEnd: return 15...30
        case .shaderFriendly: return 5...15
        case .metalExperimental: return hardware.supportsExperimentalMetal ? 30...60 : nil
        }
    }

    // MARK: - JVM arguments

    /// GC + performance flags per profile. Users can edit these; the preset diff
    /// is kept so "Reset to preset" is exact.
    func jvmArguments(for profile: PerformanceProfile, ramMB: Int) -> [String] {
        switch profile {
        case .safe:
            return []
        case .lowEnd:
            return [
                "-XX:+UseG1GC",
                "-XX:MaxGCPauseMillis=50",
                "-XX:G1HeapRegionSize=16M",
                "-XX:+ParallelRefProcEnabled",
                "-XX:+PerfDisableSharedMem"
            ]
        case .balanced, .shaderFriendly:
            // Aikar-style G1 tuning adapted for clients: short pauses, early
            // mixed collections, no survivor churn.
            return [
                "-XX:+UseG1GC",
                "-XX:MaxGCPauseMillis=37",
                "-XX:+ParallelRefProcEnabled",
                "-XX:+DisableExplicitGC",
                "-XX:G1HeapRegionSize=16M",
                "-XX:G1NewSizePercent=28",
                "-XX:G1MaxNewSizePercent=40",
                "-XX:G1ReservePercent=20",
                "-XX:G1HeapWastePercent=5",
                "-XX:G1MixedGCCountTarget=4",
                "-XX:InitiatingHeapOccupancyPercent=15",
                "-XX:SurvivorRatio=32",
                "-XX:MaxTenuringThreshold=1",
                "-XX:+UseStringDeduplication",
                "-XX:+PerfDisableSharedMem",
                "-XX:+AlwaysPreTouch"
            ]
        case .maxFPS:
            // Generational ZGC: sub-millisecond pauses, ideal on many-core
            // Apple Silicon with a decent heap. Plus a bigger JIT code cache
            // and LWJGL parameter-check elision.
            var args = [
                "-XX:+UseZGC",
                "-XX:+ZGenerational",
                "-XX:+AlwaysPreTouch",
                "-XX:+UseStringDeduplication",
                "-XX:+PerfDisableSharedMem",
                "-XX:ReservedCodeCacheSize=400M",
                "-Dorg.lwjgl.util.NoChecks=true"
            ]
            if ramMB < 4096 {
                // ZGC needs headroom; fall back to tuned G1 on small heaps.
                args = [
                    "-XX:+UseG1GC",
                    "-XX:MaxGCPauseMillis=25",
                    "-XX:+ParallelRefProcEnabled",
                    "-XX:+AlwaysPreTouch",
                    "-XX:+PerfDisableSharedMem",
                    "-Dorg.lwjgl.util.NoChecks=true"
                ]
            }
            return args
        }
    }

    /// Apply a preset to an instance (returns the modified copy).
    func apply(profile: PerformanceProfile, to instance: Instance, rendererManager: RendererManager) -> Instance {
        var updated = instance
        updated.performanceProfile = profile
        let ram = recommendedRAM(for: profile)
        updated.memory = .init(minMB: min(1024, ram), maxMB: ram)
        updated.jvmArgs = jvmArguments(for: profile, ramMB: ram)
        switch profile {
        case .safe: updated.renderer.mode = .safe
        case .lowEnd: updated.renderer.mode = .lowEnd
        case .shaderFriendly: updated.renderer.mode = .shaderFriendly
        case .balanced, .maxFPS:
            updated.renderer.mode = rendererManager.recommendedMode()
        }
        return updated
    }
}
