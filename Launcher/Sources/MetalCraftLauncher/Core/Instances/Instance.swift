import Foundation

enum LoaderType: String, Codable, CaseIterable, Identifiable {
    case vanilla, fabric, quilt, forge, neoforge
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vanilla: "Vanilla"
        case .fabric: "Fabric"
        case .quilt: "Quilt"
        case .forge: "Forge"
        case .neoforge: "NeoForge"
        }
    }

    /// Loaders the MetalCraft Engine mod currently supports.
    var supportsMetalCraftEngine: Bool { self == .fabric || self == .quilt }
}

enum PerformanceProfile: String, Codable, CaseIterable, Identifiable {
    case balanced, maxFPS, lowEnd, shaderFriendly, safe
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: "Balanced"
        case .maxFPS: "Max FPS"
        case .lowEnd: "Low-End"
        case .shaderFriendly: "Shader-Friendly"
        case .safe: "Safe"
        }
    }
}

struct Instance: Codable, Identifiable, Equatable {
    struct Loader: Codable, Equatable {
        var type: LoaderType
        var version: String?
    }

    struct Java: Codable, Equatable {
        var path: String?          // custom Java executable, nil = managed
        var majorOverride: Int?    // force a Java major version, nil = auto
    }

    struct Memory: Codable, Equatable {
        var minMB: Int
        var maxMB: Int
    }

    struct Resolution: Codable, Equatable {
        var width: Int
        var height: Int
        var fullscreen: Bool
    }

    struct Renderer: Codable, Equatable {
        var mode: RendererMode
        var crashCounts: [String: Int] = [:]
    }

    struct ModrinthLink: Codable, Equatable {
        var projectId: String
        var versionId: String
    }

    struct ImportOrigin: Codable, Equatable {
        var launcher: String
        var path: String
        var date: Date
    }

    var schemaVersion: Int = 1
    let id: UUID
    var name: String
    var icon: String = "grass_block"
    var created: Date = Date()
    var lastPlayed: Date?
    var totalPlayTimeSeconds: Int = 0
    var minecraftVersion: String
    var loader: Loader
    var java: Java = Java()
    var memory: Memory = Memory(minMB: 1024, maxMB: 4096)
    var jvmArgs: [String] = []
    var resolution: Resolution = Resolution(width: 1280, height: 720, fullscreen: false)
    var renderer: Renderer = Renderer(mode: .macOptimizedGL)
    var performanceProfile: PerformanceProfile = .balanced
    var modrinth: ModrinthLink?
    var importedFrom: ImportOrigin?
    var notes: String = ""

    var gameDir: URL { Paths.gameDir(id) }
    var dir: URL { Paths.instanceDir(id) }
}
