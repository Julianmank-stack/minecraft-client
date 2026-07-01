import Foundation

/// All launcher data lives under ~/Library/Application Support/MetalCraft,
/// following macOS conventions. Nothing is written outside this tree except
/// what the user explicitly exports.
enum Paths {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MetalCraft", isDirectory: true)
    }

    static var instances: URL { root.appendingPathComponent("instances", isDirectory: true) }
    static var meta: URL { root.appendingPathComponent("meta", isDirectory: true) }
    static var libraries: URL { root.appendingPathComponent("libraries", isDirectory: true) }
    static var assets: URL { root.appendingPathComponent("assets", isDirectory: true) }
    static var javaRuntimes: URL { root.appendingPathComponent("java", isDirectory: true) }
    static var skins: URL { root.appendingPathComponent("skins", isDirectory: true) }
    static var run: URL { root.appendingPathComponent("run", isDirectory: true) }

    static var launcherSettings: URL { root.appendingPathComponent("launcher.json") }
    static var accountsFile: URL { root.appendingPathComponent("accounts.json") }
    static var serversFile: URL { root.appendingPathComponent("servers.json") }

    static func instanceDir(_ id: UUID) -> URL {
        instances.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func gameDir(_ id: UUID) -> URL {
        instanceDir(id).appendingPathComponent(".minecraft", isDirectory: true)
    }

    static func rendererLogDir(_ id: UUID) -> URL {
        gameDir(id).appendingPathComponent("logs/renderer", isDirectory: true)
    }

    static func ensureDirectories() throws {
        for dir in [root, instances, meta, libraries, assets, javaRuntimes, skins, run] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
