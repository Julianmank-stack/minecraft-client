import Foundation

/// Resolves Fabric and Quilt loader profiles from their official meta servers.
/// A profile contributes: the loader main class, extra libraries (Maven
/// coordinates), and extra JVM/game arguments merged over the vanilla version.
///
/// Forge/NeoForge use installer-based patching and are not supported yet —
/// those instances launch vanilla with a warning.
final class LoaderProfileService {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum LoaderError: LocalizedError {
        case noLoaderVersion(String, String)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .noLoaderVersion(let loader, let mc):
                "No \(loader) loader version available for Minecraft \(mc)."
            case .unsupported(let loader):
                "\(loader) launching isn't supported yet — the instance will launch as vanilla."
            }
        }
    }

    struct Profile: Decodable {
        struct Library: Decodable {
            let name: String        // Maven coordinate group:artifact:version[:classifier]
            let url: String?        // Maven repository base URL
            let sha1: String?
            let size: Int?
        }
        struct Arguments: Decodable {
            let game: [String]?
            let jvm: [String]?
        }
        let mainClass: String
        let libraries: [Library]
        let arguments: Arguments?
    }

    struct Resolved {
        let loaderVersion: String
        let profile: Profile
        let defaultMavenBase: String
    }

    /// Fetch (and cache) the loader profile. `loaderVersion` nil = latest stable.
    func resolve(loader: LoaderType, minecraftVersion: String, loaderVersion: String?) async throws -> Resolved {
        let (metaBase, mavenBase): (String, String) = switch loader {
        case .fabric: ("https://meta.fabricmc.net/v2", "https://maven.fabricmc.net/")
        case .quilt: ("https://meta.quiltmc.org/v3", "https://maven.quiltmc.org/repository/release/")
        default: throw LoaderError.unsupported(loader.displayName)
        }

        let version: String
        if let loaderVersion, !loaderVersion.isEmpty {
            version = loaderVersion
        } else {
            version = try await latestLoaderVersion(metaBase: metaBase, loader: loader, minecraftVersion: minecraftVersion)
        }

        // Profiles are immutable per (mc, loader) pair — cache on disk.
        let cacheDir = Paths.meta.appendingPathComponent("loaders", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent("\(loader.rawValue)-\(minecraftVersion)-\(version).json")

        let data: Data
        if let cached = try? Data(contentsOf: cacheFile) {
            data = cached
        } else {
            let url = URL(string: "\(metaBase)/versions/loader/\(minecraftVersion)/\(version)/profile/json")!
            let (fetched, response) = try await session.data(from: url)
            guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
                throw LoaderError.noLoaderVersion(loader.displayName, minecraftVersion)
            }
            try? fetched.write(to: cacheFile, options: .atomic)
            data = fetched
        }

        return Resolved(
            loaderVersion: version,
            profile: try decoder.decode(Profile.self, from: data),
            defaultMavenBase: mavenBase
        )
    }

    private func latestLoaderVersion(metaBase: String, loader: LoaderType, minecraftVersion: String) async throws -> String {
        struct Entry: Decodable {
            struct Loader: Decodable {
                let version: String
                let stable: Bool?
            }
            let loader: Loader
        }
        let url = URL(string: "\(metaBase)/versions/loader/\(minecraftVersion)")!
        let (data, response) = try await session.data(from: url)
        guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0),
              let entries = try? decoder.decode([Entry].self, from: data),
              !entries.isEmpty else {
            throw LoaderError.noLoaderVersion(loader.displayName, minecraftVersion)
        }
        // Fabric marks stability; Quilt lists newest-first without the flag.
        return (entries.first { $0.loader.stable == true } ?? entries[0]).loader.version
    }

    /// Maven coordinate → repository-relative path.
    /// "net.fabricmc:fabric-loader:0.16.9" →
    /// "net/fabricmc/fabric-loader/0.16.9/fabric-loader-0.16.9.jar"
    static func mavenPath(_ coordinate: String) -> String? {
        let parts = coordinate.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { return nil }
        let group = parts[0].replacingOccurrences(of: ".", with: "/")
        let artifact = parts[1]
        let version = parts[2]
        let classifier = parts.count > 3 ? "-\(parts[3])" : ""
        return "\(group)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).jar"
    }
}
