import Foundation

/// Client for the official Modrinth API (https://docs.modrinth.com).
/// Sends a descriptive User-Agent as required by Modrinth's API rules.
final class ModrinthAPI {
    static let base = URL(string: "https://api.modrinth.com/v2")!
    static let userAgent = "metalcraft-launcher/0.1 (github.com/Julianmank-stack/minecraft-client)"

    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum ProjectType: String {
        case modpack, mod, shader, resourcepack
    }

    // MARK: - Models

    struct SearchHit: Decodable, Identifiable {
        let projectId: String
        let title: String
        let description: String
        let author: String
        let downloads: Int
        let iconUrl: String?
        let categories: [String]
        let versions: [String]

        var id: String { projectId }

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case title, description, author, downloads
            case iconUrl = "icon_url"
            case categories, versions
        }
    }

    struct SearchResponse: Decodable {
        let hits: [SearchHit]
        let totalHits: Int
        enum CodingKeys: String, CodingKey {
            case hits
            case totalHits = "total_hits"
        }
    }

    struct Project: Decodable {
        struct GalleryImage: Decodable { let url: String; let title: String? }
        struct License: Decodable { let id: String; let name: String; let url: String? }
        let id: String
        let title: String
        let description: String
        let body: String
        let downloads: Int
        let iconUrl: String?
        let gallery: [GalleryImage]?
        let gameVersions: [String]
        let loaders: [String]
        let license: License?
        let sourceUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, title, description, body, downloads, gallery, loaders, license
            case iconUrl = "icon_url"
            case gameVersions = "game_versions"
            case sourceUrl = "source_url"
        }
    }

    struct Version: Decodable, Identifiable {
        struct File: Decodable {
            struct Hashes: Decodable { let sha1: String?; let sha512: String? }
            let url: String
            let filename: String
            let primary: Bool
            let size: Int
            let hashes: Hashes
        }
        struct Dependency: Decodable {
            let projectId: String?
            let dependencyType: String   // required | optional | incompatible | embedded
            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
                case dependencyType = "dependency_type"
            }
        }
        let id: String
        let projectId: String
        let name: String
        let versionNumber: String
        let gameVersions: [String]
        let loaders: [String]
        let files: [File]
        let dependencies: [Dependency]

        enum CodingKeys: String, CodingKey {
            case id, name, files, dependencies, loaders
            case projectId = "project_id"
            case versionNumber = "version_number"
            case gameVersions = "game_versions"
        }
    }

    // MARK: - Endpoints

    func search(
        query: String,
        type: ProjectType,
        loader: LoaderType? = nil,
        minecraftVersion: String? = nil,
        category: String? = nil,
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> SearchResponse {
        var facets: [[String]] = [["project_type:\(type.rawValue)"]]
        if let loader, loader != .vanilla { facets.append(["categories:\(loader.rawValue)"]) }
        if let minecraftVersion { facets.append(["versions:\(minecraftVersion)"]) }
        if let category { facets.append(["categories:\(category)"]) }

        var components = URLComponents(url: Self.base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "query", value: query),
            .init(name: "facets", value: String(data: try JSONEncoder().encode(facets), encoding: .utf8)),
            .init(name: "limit", value: String(limit)),
            .init(name: "offset", value: String(offset)),
            .init(name: "index", value: query.isEmpty ? "downloads" : "relevance")
        ]
        return try await get(components.url!)
    }

    func project(id: String) async throws -> Project {
        try await get(Self.base.appendingPathComponent("project/\(id)"))
    }

    func versions(projectId: String, minecraftVersion: String? = nil, loader: LoaderType? = nil) async throws -> [Version] {
        var components = URLComponents(
            url: Self.base.appendingPathComponent("project/\(projectId)/version"),
            resolvingAgainstBaseURL: false
        )!
        var query: [URLQueryItem] = []
        if let minecraftVersion { query.append(.init(name: "game_versions", value: "[\"\(minecraftVersion)\"]")) }
        if let loader, loader != .vanilla { query.append(.init(name: "loaders", value: "[\"\(loader.rawValue)\"]")) }
        if !query.isEmpty { components.queryItems = query }
        return try await get(components.url!)
    }

    /// Recursively resolve required dependencies for a version (cycle-safe).
    func resolveDependencies(of version: Version, minecraftVersion: String, loader: LoaderType) async throws -> [Version] {
        var resolved: [Version] = []
        var visited: Set<String> = [version.projectId]
        var queue = version.dependencies.filter { $0.dependencyType == "required" }.compactMap(\.projectId)

        while let projectId = queue.first {
            queue.removeFirst()
            guard visited.insert(projectId).inserted else { continue }
            let candidates = try await versions(projectId: projectId, minecraftVersion: minecraftVersion, loader: loader)
            guard let best = candidates.first else { continue }
            resolved.append(best)
            queue.append(contentsOf: best.dependencies.filter { $0.dependencyType == "required" }.compactMap(\.projectId))
        }
        return resolved
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw URLError(.badServerResponse)
        }
        return try decoder.decode(T.self, from: data)
    }
}
