import Foundation

/// Official Mojang Piston-Meta manifests. Game files are downloaded ONLY from
/// piston-meta.mojang.com / libraries.minecraft.net / resources.download.minecraft.net.
final class VersionManifestService {
    static let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
    static let assetsBase = URL(string: "https://resources.download.minecraft.net")!

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    struct Manifest: Decodable {
        struct Latest: Decodable { let release: String; let snapshot: String }
        struct Entry: Decodable {
            let id: String
            let type: String
            let url: String
            let sha1: String
        }
        let latest: Latest
        let versions: [Entry]
    }

    /// version_manifest_v2.json with a 24h on-disk cache.
    func manifest(forceRefresh: Bool = false) async throws -> Manifest {
        let cache = Paths.meta.appendingPathComponent("version_manifest_v2.json")
        if !forceRefresh,
           let attrs = try? FileManager.default.attributesOfItem(atPath: cache.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 86_400,
           let data = try? Data(contentsOf: cache) {
            return try decoder.decode(Manifest.self, from: data)
        }
        let (data, _) = try await session.data(from: Self.manifestURL)
        try? data.write(to: cache, options: .atomic)
        return try decoder.decode(Manifest.self, from: data)
    }

    /// Full version JSON, cached immutably per version id (verified by sha1).
    func versionJSON(for entry: Manifest.Entry) async throws -> VersionJSON {
        let dir = Paths.meta.appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cache = dir.appendingPathComponent("\(entry.id).json")

        if let data = try? Data(contentsOf: cache), SHA1.hex(of: data) == entry.sha1 {
            return try decoder.decode(VersionJSON.self, from: data)
        }
        let (data, _) = try await session.data(from: URL(string: entry.url)!)
        try data.write(to: cache, options: .atomic)
        return try decoder.decode(VersionJSON.self, from: data)
    }
}

// MARK: - Version JSON model (the subset the launcher needs)

struct VersionJSON: Decodable {
    struct Download: Decodable { let sha1: String; let size: Int; let url: String }
    struct Downloads: Decodable { let client: Download }
    struct JavaVersion: Decodable { let majorVersion: Int }
    struct AssetIndexRef: Decodable { let id: String; let sha1: String; let url: String; let totalSize: Int? }

    struct Rule: Decodable {
        struct OS: Decodable { let name: String?; let arch: String? }
        let action: String
        let os: OS?
        let features: [String: Bool]?
    }

    struct Artifact: Decodable { let path: String; let sha1: String; let size: Int; let url: String }

    struct Library: Decodable {
        struct Downloads: Decodable { let artifact: Artifact? }
        let name: String
        let downloads: Downloads?
        let rules: [Rule]?

        /// Library rules filtered for macOS + current architecture.
        var appliesToMacOS: Bool {
            guard let rules else { return true }
            var allowed = false
            for rule in rules {
                let osMatches = rule.os == nil || rule.os?.name == "osx"
                if rule.action == "allow" {
                    if rule.os == nil || osMatches { allowed = true }
                } else if rule.action == "disallow" {
                    if osMatches && rule.os != nil { allowed = false }
                    if rule.os == nil { allowed = false }
                }
            }
            return allowed
        }
    }

    struct Arguments: Decodable {
        let game: [ArgumentValue]?
        let jvm: [ArgumentValue]?
    }

    /// Arguments are either plain strings or rule-guarded objects.
    enum ArgumentValue: Decodable {
        case plain(String)
        case conditional(rules: [Rule], value: [String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .plain(s)
                return
            }
            struct Conditional: Decodable {
                let rules: [Rule]
                let value: ValueField
            }
            enum ValueField: Decodable {
                case one(String), many([String])
                init(from decoder: Decoder) throws {
                    let c = try decoder.singleValueContainer()
                    if let s = try? c.decode(String.self) { self = .one(s) }
                    else { self = .many(try c.decode([String].self)) }
                }
                var values: [String] {
                    switch self {
                    case .one(let s): [s]
                    case .many(let a): a
                    }
                }
            }
            let cond = try container.decode(Conditional.self)
            self = .conditional(rules: cond.rules, value: cond.value.values)
        }
    }

    let id: String
    let mainClass: String
    let downloads: Downloads
    let libraries: [Library]
    let javaVersion: JavaVersion?
    let assetIndex: AssetIndexRef
    let arguments: Arguments?
    let minecraftArguments: String?   // legacy (< 1.13)
    let type: String
}

struct AssetIndex: Decodable {
    struct Object: Decodable { let hash: String; let size: Int }
    let objects: [String: Object]
}
