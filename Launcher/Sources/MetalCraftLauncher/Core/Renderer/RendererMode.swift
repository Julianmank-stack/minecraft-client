import Foundation

/// The seven rendering modes exposed by the launcher. See docs/METALCRAFT_ENGINE.md
/// for exactly what each stage does — UI copy must never overstate this.
enum RendererMode: String, Codable, CaseIterable, Identifiable {
    case standardGL
    case macOptimizedGL
    case appleSiliconMax
    case lowEnd
    case shaderFriendly
    case metalExperimental
    case safe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standardGL: "Standard OpenGL"
        case .macOptimizedGL: "Mac Optimized OpenGL"
        case .appleSiliconMax: "Apple Silicon Max FPS"
        case .lowEnd: "Low-End Mac Mode"
        case .shaderFriendly: "Shader-Friendly Mode"
        case .metalExperimental: "Experimental Metal Renderer"
        case .safe: "Safe Mode"
        }
    }

    var summary: String {
        switch self {
        case .standardGL:
            "Vanilla rendering pipeline, completely untouched."
        case .macOptimizedGL:
            "macOS-tuned OpenGL state management, buffer strategies and frame pacing."
        case .appleSiliconMax:
            "Everything in Mac Optimized OpenGL, plus unified-memory buffer handling and aggressive chunk batching for M-series GPUs."
        case .lowEnd:
            "Reduced effects and conservative memory use for older or low-RAM Macs."
        case .shaderFriendly:
            "Only optimizations that are safe alongside Iris/shader packs."
        case .metalExperimental:
            "Experimental: renders chunk terrain with a native Metal backend. Everything else stays on OpenGL. Falls back automatically after crashes."
        case .safe:
            "All optimizations off. Maximum compatibility for troubleshooting."
        }
    }

    var isExperimental: Bool { self == .metalExperimental }

    /// Requires the MetalCraft Engine companion mod (Fabric/Quilt only).
    var requiresEngineMod: Bool {
        switch self {
        case .standardGL, .safe: false
        default: true
        }
    }

    /// Automatic downgrade chain used after repeated crashes.
    var fallback: RendererMode? {
        switch self {
        case .metalExperimental: .appleSiliconMax
        case .appleSiliconMax: .macOptimizedGL
        case .macOptimizedGL, .lowEnd, .shaderFriendly: .standardGL
        case .standardGL: .safe
        case .safe: nil
        }
    }
}
