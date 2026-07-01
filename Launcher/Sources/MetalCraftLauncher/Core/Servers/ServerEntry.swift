import Foundation

struct ServerFolder: Codable, Identifiable, Equatable {
    let id: String
    var name: String
}

struct ServerEntry: Codable, Identifiable, Equatable {
    let id: String
    var folderId: String?
    var name: String
    var address: String
    var port: UInt16 = 25565
    var notes: String = ""
    var iconBase64: String?
    var preferredInstance: UUID?

    var displayAddress: String {
        port == 25565 ? address : "\(address):\(port)"
    }
}

/// Runtime-only ping result — never persisted.
struct ServerStatus {
    let online: Bool
    let motd: String
    let playersOnline: Int
    let playersMax: Int
    let versionName: String
    let latencyMs: Int
    let faviconBase64: String?
}

final class ServerStore {
    private struct FileFormat: Codable {
        var schemaVersion = 1
        var folders: [ServerFolder]
        var servers: [ServerEntry]
    }

    func load() throws -> [ServerEntry] {
        guard let data = try? Data(contentsOf: Paths.serversFile) else { return [] }
        return try JSONDecoder().decode(FileFormat.self, from: data).servers
    }

    func loadFolders() throws -> [ServerFolder] {
        guard let data = try? Data(contentsOf: Paths.serversFile) else { return [] }
        return try JSONDecoder().decode(FileFormat.self, from: data).folders
    }

    func save(servers: [ServerEntry], folders: [ServerFolder]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(FileFormat(folders: folders, servers: servers))
            .write(to: Paths.serversFile, options: .atomic)
    }
}
