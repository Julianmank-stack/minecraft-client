import Foundation

/// Persistence for instances: one folder per instance under
/// ~/Library/Application Support/MetalCraft/instances/<uuid>/ with instance.json.
final class InstanceStore {
    private let fm = FileManager.default

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func loadAll() throws -> [Instance] {
        guard fm.fileExists(atPath: Paths.instances.path) else { return [] }
        let dirs = try fm.contentsOfDirectory(at: Paths.instances, includingPropertiesForKeys: nil)
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("instance.json")) else { return nil }
            return try? decoder.decode(Instance.self, from: data)
        }
        .sorted { ($0.lastPlayed ?? $0.created) > ($1.lastPlayed ?? $1.created) }
    }

    func save(_ instance: Instance) throws {
        let dir = instance.dir
        try fm.createDirectory(at: instance.gameDir, withIntermediateDirectories: true)
        try encoder.encode(instance)
            .write(to: dir.appendingPathComponent("instance.json"), options: .atomic)
    }

    func create(name: String, minecraftVersion: String, loader: Instance.Loader) throws -> Instance {
        let instance = Instance(id: UUID(), name: name, minecraftVersion: minecraftVersion, loader: loader)
        try save(instance)
        return instance
    }

    func delete(_ id: UUID) throws {
        // Move to Trash rather than hard-delete, matching macOS expectations.
        try fm.trashItem(at: Paths.instanceDir(id), resultingItemURL: nil)
    }

    func duplicate(_ instance: Instance, newName: String) throws -> Instance {
        var copy = Instance(id: UUID(), name: newName,
                            minecraftVersion: instance.minecraftVersion, loader: instance.loader)
        copy.icon = instance.icon
        copy.java = instance.java
        copy.memory = instance.memory
        copy.jvmArgs = instance.jvmArgs
        copy.resolution = instance.resolution
        copy.renderer = Instance.Renderer(mode: instance.renderer.mode)
        copy.performanceProfile = instance.performanceProfile
        copy.fpsCap = instance.fpsCap
        copy.thermalGuard = instance.thermalGuard
        copy.notes = instance.notes
        try fm.createDirectory(at: copy.dir, withIntermediateDirectories: true)
        try fm.copyItem(at: instance.gameDir, to: copy.gameDir)
        try save(copy)
        return copy
    }

    func recordPlaySession(_ id: UUID, seconds: Int) throws {
        guard var instance = try load(id) else { return }
        instance.lastPlayed = Date()
        instance.totalPlayTimeSeconds += seconds
        try save(instance)
    }

    func setRendererMode(_ id: UUID, mode: RendererMode) throws {
        guard var instance = try load(id) else { return }
        instance.renderer.mode = mode
        try save(instance)
    }

    func load(_ id: UUID) throws -> Instance? {
        let url = Paths.instanceDir(id).appendingPathComponent("instance.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try decoder.decode(Instance.self, from: data)
    }
}
