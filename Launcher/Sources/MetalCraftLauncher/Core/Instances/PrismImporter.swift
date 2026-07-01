import Foundation

/// Imports existing Prism Launcher (and legacy PolyMC) instances.
/// The original Prism instance is never modified. See docs/PRISM_IMPORT.md.
final class PrismImporter {
    private let instanceStore: InstanceStore

    init(instanceStore: InstanceStore) {
        self.instanceStore = instanceStore
    }

    enum PrismError: LocalizedError {
        case notAPrismInstance
        var errorDescription: String? { "This folder doesn't look like a Prism Launcher instance." }
    }

    static let defaultScanLocations: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PrismLauncher/instances"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PolyMC/instances")
    ]

    struct Candidate: Identifiable {
        let id = UUID()
        let folder: URL
        let name: String
        let minecraftVersion: String
        let loader: Instance.Loader
        let modCount: Int
    }

    /// Scan default Prism locations for importable instances.
    func detect() -> [Candidate] {
        var candidates: [Candidate] = []
        for root in Self.defaultScanLocations {
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                if let candidate = try? inspect(folder: child) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    /// Validate a folder (also used for drag-and-drop) and preview its contents.
    func inspect(folder: URL) throws -> Candidate {
        let cfg = folder.appendingPathComponent("instance.cfg")
        guard FileManager.default.fileExists(atPath: cfg.path) else { throw PrismError.notAPrismInstance }
        let config = try parseCfg(at: cfg)

        let pack = try parsePack(at: folder.appendingPathComponent("mmc-pack.json"))
        let gameDir = Self.gameDir(in: folder)
        let modCount = (try? FileManager.default.contentsOfDirectory(
            at: gameDir.appendingPathComponent("mods"), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "jar" }.count) ?? 0

        return Candidate(
            folder: folder,
            name: config["name"] ?? folder.lastPathComponent,
            minecraftVersion: pack.minecraft ?? "unknown",
            loader: pack.loader,
            modCount: modCount
        )
    }

    /// Perform the import: copy game content, map settings, create instance.json.
    func importInstance(_ candidate: Candidate, onProgress: @escaping @Sendable (Double, String) -> Void) throws -> Instance {
        onProgress(0.05, "Reading Prism configuration…")
        let cfg = try parseCfg(at: candidate.folder.appendingPathComponent("instance.cfg"))

        var instance = try instanceStore.create(
            name: candidate.name,
            minecraftVersion: candidate.minecraftVersion,
            loader: candidate.loader
        )

        if let javaPath = cfg["JavaPath"], !javaPath.isEmpty { instance.java.path = javaPath }
        if let maxMem = cfg["MaxMemAlloc"].flatMap({ Int($0) }) { instance.memory.maxMB = maxMem }
        if let minMem = cfg["MinMemAlloc"].flatMap({ Int($0) }) { instance.memory.minMB = minMem }
        if let jvmArgs = cfg["JvmArgs"], !jvmArgs.isEmpty {
            instance.jvmArgs = jvmArgs.split(separator: " ").map(String.init)
        }
        if let notes = cfg["notes"], !notes.isEmpty { instance.notes = notes }
        instance.importedFrom = .init(launcher: "prism", path: candidate.folder.path, date: Date())

        // Copy game content (fast on APFS thanks to clonefile)
        onProgress(0.2, "Copying game files…")
        let source = Self.gameDir(in: candidate.folder)
        let fm = FileManager.default
        if fm.fileExists(atPath: source.path) {
            try? fm.removeItem(at: instance.gameDir)
            try fm.copyItem(at: source, to: instance.gameDir)
        }

        onProgress(0.9, "Saving instance…")
        try instanceStore.save(instance)
        onProgress(1.0, "Imported \(candidate.name)")
        return instance
    }

    // MARK: - Parsing

    private static func gameDir(in folder: URL) -> URL {
        let dotMinecraft = folder.appendingPathComponent(".minecraft")
        if FileManager.default.fileExists(atPath: dotMinecraft.path) { return dotMinecraft }
        return folder.appendingPathComponent("minecraft")
    }

    /// instance.cfg is INI-style key=value (possibly with an INI [General] header).
    private func parseCfg(at url: URL) throws -> [String: String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard !line.hasPrefix("["), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    private struct PackInfo {
        let minecraft: String?
        let loader: Instance.Loader
    }

    /// mmc-pack.json lists components (minecraft + loader + intermediary etc).
    private func parsePack(at url: URL) throws -> PackInfo {
        struct Pack: Decodable {
            struct Component: Decodable {
                let uid: String
                let version: String?
            }
            let components: [Component]
        }
        guard let data = try? Data(contentsOf: url) else {
            return PackInfo(minecraft: nil, loader: .init(type: .vanilla, version: nil))
        }
        let pack = try JSONDecoder().decode(Pack.self, from: data)

        var minecraft: String?
        var loader = Instance.Loader(type: .vanilla, version: nil)
        for component in pack.components {
            switch component.uid {
            case "net.minecraft": minecraft = component.version
            case "net.fabricmc.fabric-loader": loader = .init(type: .fabric, version: component.version)
            case "org.quiltmc.quilt-loader": loader = .init(type: .quilt, version: component.version)
            case "net.minecraftforge": loader = .init(type: .forge, version: component.version)
            case "net.neoforged": loader = .init(type: .neoforge, version: component.version)
            default: break
            }
        }
        return PackInfo(minecraft: minecraft, loader: loader)
    }
}
