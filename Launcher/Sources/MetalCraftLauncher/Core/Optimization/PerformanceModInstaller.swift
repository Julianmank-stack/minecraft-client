import Foundation

/// One-click installer for the proven Fabric/Quilt performance mod stack.
///
/// Every entry is Sodium-compatible and attacks a *different* bottleneck —
/// chunk rendering, game-tick logic, memory churn, networking, entity
/// overdraw, chunk generation — so the set composes without conflicts.
/// "Already installed" detection is filename-prefix based, matching how
/// Modrinth names primary files (e.g. `lithium-fabric-mc1.21.4-0.14.jar`).
struct PerformanceModInstaller {
    struct CuratedMod: Identifiable {
        let slug: String            // Modrinth project slug
        let name: String
        let purpose: String
        let detectPrefixes: [String]
        var id: String { slug }
    }

    static let curated: [CuratedMod] = [
        .init(slug: "sodium", name: "Sodium",
              purpose: "Rewrites the chunk renderer — the single biggest FPS win",
              detectPrefixes: ["sodium-fabric", "sodium-quilt", "sodium-mc", "sodium-neoforge"]),
        .init(slug: "lithium", name: "Lithium",
              purpose: "Optimizes game-tick logic (AI, physics, block ticking) without changing gameplay",
              detectPrefixes: ["lithium"]),
        .init(slug: "ferrite-core", name: "FerriteCore",
              purpose: "Cuts memory use — less GC pressure means fewer micro-stutters",
              detectPrefixes: ["ferritecore"]),
        .init(slug: "krypton", name: "Krypton",
              purpose: "Optimizes the networking stack for smoother multiplayer",
              detectPrefixes: ["krypton"]),
        .init(slug: "entityculling", name: "Entity Culling",
              purpose: "Skips rendering entities hidden behind walls",
              detectPrefixes: ["entityculling"]),
        .init(slug: "moreculling", name: "More Culling",
              purpose: "Culls hidden block faces, item models and leaves",
              detectPrefixes: ["moreculling"]),
        .init(slug: "immediatelyfast", name: "ImmediatelyFast",
              purpose: "Batches HUD/GUI immediate-mode rendering",
              detectPrefixes: ["immediatelyfast"]),
        .init(slug: "modernfix", name: "ModernFix",
              purpose: "Broad performance fixes and much faster launch times",
              detectPrefixes: ["modernfix"]),
        .init(slug: "dynamic-fps", name: "Dynamic FPS",
              purpose: "Idles the game when unfocused — saves thermal headroom for when you're playing",
              detectPrefixes: ["dynamic-fps", "dynamicfps"]),
        .init(slug: "c2me-fabric", name: "C2ME",
              purpose: "Multithreads chunk loading/generation across all CPU cores",
              detectPrefixes: ["c2me"]),
        .init(slug: "badoptimizations", name: "BadOptimizations",
              purpose: "Micro-optimizes lighting, time and random-tick logic",
              detectPrefixes: ["badoptimizations"]),
        .init(slug: "ebe", name: "Enhanced Block Entities",
              purpose: "Renders chests/signs through the fast chunk path",
              detectPrefixes: ["enhancedblockentities"]),
    ]

    /// Library dependencies that must not be duplicated when a jar is already
    /// present under a different version (duplicate mod IDs crash the loader).
    private static let knownDependencyPrefixes = [
        "fabric-api", "qfapi", "quilted-fabric-api", "cloth-config", "yetanotherconfiglib", "yacl"
    ]

    enum InstallError: LocalizedError {
        case unsupportedLoader
        var errorDescription: String? {
            "Performance mods need a Fabric or Quilt instance."
        }
    }

    struct Summary {
        var installed: [String] = []     // newly installed
        var skipped: [String] = []       // already present
        var unavailable: [String] = []   // no build for this Minecraft version
    }

    let api: ModrinthAPI

    // MARK: - Detection

    static func installedJarNames(in instance: Instance) -> [String] {
        let modsDir = instance.gameDir.appendingPathComponent("mods")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: modsDir.path)) ?? []
        return names.map { $0.lowercased() }.filter { $0.hasSuffix(".jar") }
    }

    static func isInstalled(_ mod: CuratedMod, jarNames: [String]) -> Bool {
        jarNames.contains { name in mod.detectPrefixes.contains(where: name.hasPrefix) }
    }

    static func missingMods(in instance: Instance) -> [CuratedMod] {
        let jars = installedJarNames(in: instance)
        return curated.filter { !isInstalled($0, jarNames: jars) }
    }

    // MARK: - Install

    /// Installs every curated mod that is missing and has a compatible build,
    /// resolving required libraries (e.g. Fabric API) along the way.
    func installMissing(
        into instance: Instance,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> Summary {
        guard instance.loader.type == .fabric || instance.loader.type == .quilt else {
            throw InstallError.unsupportedLoader
        }

        var summary = Summary()
        let jarNames = Self.installedJarNames(in: instance)
        var items: [DownloadManager.Item] = []
        var queuedProjects = Set<String>()

        for mod in Self.curated {
            if Self.isInstalled(mod, jarNames: jarNames) {
                summary.skipped.append(mod.name)
                continue
            }
            onProgress("Resolving \(mod.name)…")
            guard let version = try await bestVersion(slug: mod.slug, instance: instance) else {
                summary.unavailable.append(mod.name)
                continue
            }
            queue(version, into: &items, queued: &queuedProjects, instance: instance)

            let deps = (try? await api.resolveDependencies(
                of: version,
                minecraftVersion: instance.minecraftVersion,
                loader: resolveLoader(for: instance)
            )) ?? []
            for dep in deps {
                let filename = (dep.files.first(where: \.primary) ?? dep.files.first)?.filename.lowercased() ?? ""
                // A known library already in mods/ (any version) must not be duplicated.
                if let prefix = Self.knownDependencyPrefixes.first(where: filename.hasPrefix),
                   jarNames.contains(where: { $0.hasPrefix(prefix) }) {
                    continue
                }
                queue(dep, into: &items, queued: &queuedProjects, instance: instance)
            }
            summary.installed.append(mod.name)
        }

        guard !items.isEmpty else { return summary }
        onProgress("Downloading \(items.count) files…")
        try await DownloadManager().download(items) { done, total in
            onProgress("Downloading \(done)/\(total)…")
        }
        return summary
    }

    private func queue(
        _ version: ModrinthAPI.Version,
        into items: inout [DownloadManager.Item],
        queued: inout Set<String>,
        instance: Instance
    ) {
        guard queued.insert(version.projectId).inserted,
              let file = version.files.first(where: \.primary) ?? version.files.first,
              let url = URL(string: file.url) else { return }
        items.append(.init(
            url: url,
            destination: instance.gameDir.appendingPathComponent("mods/\(file.filename)"),
            sha1: file.hashes.sha1,
            size: file.size
        ))
    }

    private func bestVersion(slug: String, instance: Instance) async throws -> ModrinthAPI.Version? {
        if let version = try await api.versions(
            projectId: slug,
            minecraftVersion: instance.minecraftVersion,
            loader: instance.loader.type
        ).first {
            return version
        }
        // Quilt loads Fabric mods; fall back when no Quilt-tagged build exists.
        if instance.loader.type == .quilt {
            return try await api.versions(
                projectId: slug,
                minecraftVersion: instance.minecraftVersion,
                loader: .fabric
            ).first
        }
        return nil
    }

    private func resolveLoader(for instance: Instance) -> LoaderType {
        instance.loader.type == .quilt ? .fabric : instance.loader.type
    }
}
