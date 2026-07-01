import Foundation

/// Decides which renderer modes are available on this Mac, produces the
/// metalcraft.json config the engine mod reads, and drives the crash-count
/// based automatic fallback chain.
final class RendererManager {
    let hardware: HardwareReport
    private let maxCrashesBeforeFallback = 2

    init(hardware: HardwareReport) {
        self.hardware = hardware
    }

    // MARK: - Availability

    struct ModeAvailability {
        let mode: RendererMode
        let available: Bool
        let reason: String?     // shown greyed-out in the UI when unavailable
    }

    func availability(for instance: Instance) -> [ModeAvailability] {
        RendererMode.allCases.map { mode in
            switch mode {
            case .appleSiliconMax where !hardware.isAppleSilicon:
                return .init(mode: mode, available: false, reason: "Requires an Apple Silicon Mac")
            case .metalExperimental where !hardware.supportsExperimentalMetal:
                return .init(mode: mode, available: false, reason: "Requires macOS 13+ and a Metal 3 GPU")
            case .metalExperimental where !instance.loader.type.supportsMetalCraftEngine:
                return .init(mode: mode, available: false, reason: "Requires Fabric or Quilt")
            case _ where mode.requiresEngineMod && !instance.loader.type.supportsMetalCraftEngine
                     && mode != .macOptimizedGL && mode != .lowEnd && mode != .shaderFriendly:
                return .init(mode: mode, available: false, reason: "Requires Fabric or Quilt")
            default:
                return .init(mode: mode, available: true, reason: nil)
            }
        }
    }

    /// Hardware-based recommendation (the Experimental Metal Renderer is never
    /// auto-recommended; it is opt-in only).
    func recommendedMode() -> RendererMode {
        if hardware.isAppleSilicon && hardware.supportsMetal3 { return .appleSiliconMax }
        if hardware.isAppleSilicon { return .macOptimizedGL }
        if hardware.physicalMemoryMB < 8192 { return .lowEnd }
        return .macOptimizedGL
    }

    // MARK: - Engine config (metalcraft.json)

    struct EngineConfig: Codable {
        var schemaVersion = 1
        var mode: String
        var framePacing: Bool
        var unifiedMemoryHints: Bool
        var chunkBatching: String
        var metal: Metal
        var safety: Safety

        struct Metal: Codable {
            var enabled: Bool
            var terrainTakeover: Bool
        }

        struct Safety: Codable {
            var maxCrashesBeforeFallback: Int
            var rendererLogDir: String
        }
    }

    func engineConfig(for instance: Instance) -> EngineConfig {
        let mode = instance.renderer.mode
        return EngineConfig(
            mode: mode.rawValue,
            framePacing: mode != .safe && mode != .standardGL,
            unifiedMemoryHints: hardware.hasUnifiedMemory && (mode == .appleSiliconMax || mode == .metalExperimental),
            chunkBatching: {
                switch mode {
                case .appleSiliconMax, .metalExperimental: "aggressive"
                case .lowEnd, .shaderFriendly: "conservative"
                default: "off"
                }
            }(),
            metal: .init(
                enabled: mode == .metalExperimental,
                terrainTakeover: mode == .metalExperimental
            ),
            safety: .init(
                maxCrashesBeforeFallback: maxCrashesBeforeFallback,
                rendererLogDir: "logs/renderer"
            )
        )
    }

    func writeEngineConfig(for instance: Instance) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(engineConfig(for: instance))
            .write(to: instance.dir.appendingPathComponent("metalcraft.json"), options: .atomic)
    }

    // MARK: - Crash-driven fallback

    /// Registers a renderer-attributed crash. Returns the mode to fall back to
    /// when the crash threshold is reached, or nil to stay on the current mode.
    func registerCrashAndMaybeFallback(instance: Instance) -> RendererMode? {
        let mode = instance.renderer.mode
        let count = (instance.renderer.crashCounts[mode.rawValue] ?? 0) + 1
        guard count >= maxCrashesBeforeFallback, let fallback = mode.fallback else { return nil }
        return fallback
    }

    /// Detects a stale startup handshake — the mod wrote "starting" but never
    /// reached "ok", meaning the renderer died before its first frames (covers
    /// GPU hangs where no crash report exists).
    func hasStaleHandshake(instance: Instance) -> Bool {
        let url = Paths.rendererLogDir(instance.id).appendingPathComponent("handshake.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = obj["state"] as? String else { return false }
        return state == "starting"
    }
}
