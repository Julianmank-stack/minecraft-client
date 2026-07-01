import Foundation

/// Installs Modrinth modpacks (.mrpack files) into new instances.
/// An .mrpack is a zip containing modrinth.index.json + overrides/.
final class MrPackInstaller {
    private let downloads = DownloadManager()
    private let instanceStore: InstanceStore

    init(instanceStore: InstanceStore) {
        self.instanceStore = instanceStore
    }

    enum MrPackError: LocalizedError {
        case invalidPack
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .invalidPack: "This file is not a valid Modrinth modpack."
            case .unsafePath(let p): "Modpack contains an unsafe file path: \(p)"
            }
        }
    }

    struct Index: Decodable {
        struct File: Decodable {
            struct Hashes: Decodable { let sha1: String; let sha512: String }
            struct Env: Decodable { let client: String? }
            let path: String
            let hashes: Hashes
            let downloads: [String]
            let fileSize: Int
            let env: Env?
        }
        let formatVersion: Int
        let name: String
        let versionId: String
        let files: [File]
        let dependencies: [String: String]
    }

    /// Install from a local .mrpack (drag-and-drop or downloaded from Modrinth).
    func install(
        mrpackAt url: URL,
        modrinthLink: Instance.ModrinthLink? = nil,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> Instance {
        onProgress(0.02, "Reading modpack…")
        let staging = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mrpack-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Self.unzip(url, to: staging)

        let indexURL = staging.appendingPathComponent("modrinth.index.json")
        guard let indexData = try? Data(contentsOf: indexURL) else { throw MrPackError.invalidPack }
        let index = try JSONDecoder().decode(Index.self, from: indexData)

        // Create instance from pack dependencies
        let loader: Instance.Loader
        if let fabric = index.dependencies["fabric-loader"] {
            loader = .init(type: .fabric, version: fabric)
        } else if let quilt = index.dependencies["quilt-loader"] {
            loader = .init(type: .quilt, version: quilt)
        } else if let forge = index.dependencies["forge"] {
            loader = .init(type: .forge, version: forge)
        } else if let neo = index.dependencies["neoforge"] {
            loader = .init(type: .neoforge, version: neo)
        } else {
            loader = .init(type: .vanilla, version: nil)
        }
        guard let mcVersion = index.dependencies["minecraft"] else { throw MrPackError.invalidPack }

        var instance = try instanceStore.create(name: index.name, minecraftVersion: mcVersion, loader: loader)
        instance.modrinth = modrinthLink
        try instanceStore.save(instance)

        // Download pack files (zip-slip guarded, sha1 verified)
        onProgress(0.1, "Downloading modpack files…")
        let gameDir = instance.gameDir.standardizedFileURL
        var items: [DownloadManager.Item] = []
        for file in index.files {
            if file.env?.client == "unsupported" { continue }
            let dest = gameDir.appendingPathComponent(file.path).standardizedFileURL
            guard dest.path.hasPrefix(gameDir.path + "/") else { throw MrPackError.unsafePath(file.path) }
            guard let source = file.downloads.first, let sourceURL = URL(string: source) else { continue }
            items.append(.init(url: sourceURL, destination: dest, sha1: file.hashes.sha1, size: file.fileSize))
        }
        try await downloads.download(items) { done, total in
            onProgress(0.1 + 0.8 * (total == 0 ? 1 : Double(done) / Double(total)), "Downloading files… (\(done)/\(total))")
        }

        // Apply overrides/ then client-overrides/
        onProgress(0.92, "Applying overrides…")
        for name in ["overrides", "client-overrides"] {
            let overrides = staging.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: overrides.path) else { continue }
            try Self.merge(from: overrides, into: gameDir)
        }

        onProgress(1.0, "Installed \(index.name)")
        return instance
    }

    // MARK: - Helpers

    static func unzip(_ archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", archive.path, "-d", destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw MrPackError.invalidPack }
    }

    private static func merge(from source: URL, into destination: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)
            if isDir.boolValue {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                try merge(from: item, into: target)
            } else {
                try? fm.removeItem(at: target)
                try fm.copyItem(at: item, to: target)
            }
        }
    }
}
