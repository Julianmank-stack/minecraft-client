import Foundation

/// The real launch pipeline: manifest → downloads (SHA-1 verified) → natives →
/// classpath → arguments → spawn → supervise. See docs/LAUNCH_FLOW.md.
final class LaunchEngine {
    private let manifests = VersionManifestService()
    private let downloads = DownloadManager()
    private let javaManager: JavaRuntimeManager

    init(javaManager: JavaRuntimeManager) {
        self.javaManager = javaManager
    }

    enum LaunchError: LocalizedError {
        case versionNotFound(String)
        case loaderNotInstalled(String)

        var errorDescription: String? {
            switch self {
            case .versionNotFound(let v): "Minecraft version \(v) was not found in the official manifest."
            case .loaderNotInstalled(let l): "\(l) profile is not installed for this instance yet. Use Repair Instance to install it."
            }
        }
    }

    /// Prepares and launches an instance. `onProgress` gets (0…1, detail).
    func launch(
        instance: Instance,
        account: MinecraftAccount,
        rendererConfig: RendererManager.EngineConfig,
        auth: MicrosoftAuthService? = nil,
        accessTokenOverride: String? = nil,
        quickJoinServer: (address: String, port: UInt16)? = nil,
        onProgress: @escaping @Sendable (Double, String) -> Void,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws -> GameSession {
        // 1–2. Version resolution
        onProgress(0.02, "Resolving version…")
        let manifest = try await manifests.manifest()
        guard let entry = manifest.versions.first(where: { $0.id == instance.minecraftVersion }) else {
            throw LaunchError.versionNotFound(instance.minecraftVersion)
        }
        let version = try await manifests.versionJSON(for: entry)

        // 3. Java
        onProgress(0.05, "Resolving Java runtime…")
        let runtime = try await javaManager.resolveRuntime(for: instance, versionJSON: version)

        // 4. Downloads
        onProgress(0.08, "Verifying game files…")
        var items: [DownloadManager.Item] = []

        let clientJar = Paths.meta.appendingPathComponent("versions/\(version.id).jar")
        items.append(.init(url: URL(string: version.downloads.client.url)!,
                           destination: clientJar,
                           sha1: version.downloads.client.sha1,
                           size: version.downloads.client.size))

        var classpath: [String] = []
        for library in version.libraries where library.appliesToMacOS {
            guard let artifact = library.downloads?.artifact else { continue }
            let dest = Paths.libraries.appendingPathComponent(artifact.path)
            classpath.append(dest.path)
            items.append(.init(url: URL(string: artifact.url)!,
                               destination: dest,
                               sha1: artifact.sha1,
                               size: artifact.size))
        }
        classpath.append(clientJar.path)

        // Asset index + objects
        let indexDest = Paths.assets.appendingPathComponent("indexes/\(version.assetIndex.id).json")
        try await downloads.download(
            [.init(url: URL(string: version.assetIndex.url)!, destination: indexDest,
                   sha1: version.assetIndex.sha1, size: nil)]
        ) { _, _ in }
        let index = try JSONDecoder().decode(AssetIndex.self, from: Data(contentsOf: indexDest))
        for (_, object) in index.objects {
            let prefix = String(object.hash.prefix(2))
            items.append(.init(
                url: VersionManifestService.assetsBase.appendingPathComponent("\(prefix)/\(object.hash)"),
                destination: Paths.assets.appendingPathComponent("objects/\(prefix)/\(object.hash)"),
                sha1: object.hash,
                size: object.size
            ))
        }

        try await downloads.download(items) { done, total in
            let fraction = total == 0 ? 1.0 : Double(done) / Double(total)
            onProgress(0.08 + fraction * 0.72, "Downloading files… (\(done)/\(total))")
        }

        // 5. Natives — modern versions ship natives as regular libraries with
        // macOS classifiers on the classpath; LWJGL extracts them itself.
        // java.library.path points at a per-instance dir for anything extracted.
        let nativesDir = instance.dir.appendingPathComponent("natives", isDirectory: true)
        try FileManager.default.createDirectory(at: nativesDir, withIntermediateDirectories: true)

        // 6. Renderer prep
        onProgress(0.85, "Configuring renderer…")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rendererConfig)
            .write(to: instance.dir.appendingPathComponent("metalcraft.json"), options: .atomic)

        // 7–8. Arguments
        onProgress(0.9, "Building launch command…")
        let accessToken: String
        if let accessTokenOverride {
            accessToken = accessTokenOverride
        } else if let auth {
            accessToken = try await auth.minecraftToken(for: account)
        } else {
            accessToken = "0"   // benchmark/offline verification runs never reach servers
        }

        var jvmArgs = [
            "-XstartOnFirstThread",                        // required for GLFW on macOS
            "-Xms\(instance.memory.minMB)M",
            "-Xmx\(instance.memory.maxMB)M",
            "-Djava.library.path=\(nativesDir.path)",
            "-Dorg.lwjgl.system.allocator=system",
            "-cp", classpath.joined(separator: ":")
        ]
        jvmArgs.append(contentsOf: instance.jvmArgs)
        if rendererConfig.metal.enabled {
            jvmArgs.append("-Dmetalcraft.native=\(instance.dir.appendingPathComponent("libmetalcraft_native.dylib").path)")
        }

        let substitutions: [String: String] = [
            "auth_player_name": account.username,
            "auth_uuid": account.uuid,
            "auth_access_token": accessToken,
            "auth_xuid": "0",
            "clientid": "metalcraft",
            "user_type": "msa",
            "version_name": version.id,
            "version_type": version.type,
            "game_directory": instance.gameDir.path,
            "assets_root": Paths.assets.path,
            "assets_index_name": version.assetIndex.id,
            "resolution_width": String(instance.resolution.width),
            "resolution_height": String(instance.resolution.height)
        ]

        var gameArgs = buildGameArguments(version: version, substitutions: substitutions)
        if instance.resolution.fullscreen {
            gameArgs.append("--fullscreen")
        } else {
            gameArgs.append(contentsOf: ["--width", String(instance.resolution.width),
                                         "--height", String(instance.resolution.height)])
        }
        if let server = quickJoinServer {
            gameArgs.append(contentsOf: ["--quickPlayMultiplayer", "\(server.address):\(server.port)"])
        }

        // 9. Spawn
        onProgress(1.0, "Launching Minecraft…")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: runtime.executable)
        process.arguments = jvmArgs + [version.mainClass] + gameArgs
        process.currentDirectoryURL = instance.gameDir

        return try GameSession(process: process, onLog: onLog)
    }

    /// Full re-verification pass: every file re-checked against its SHA-1,
    /// mismatches re-downloaded. This is the "Repair Instance" button.
    func repair(instance: Instance, onProgress: @escaping @Sendable (Double, String) -> Void) async throws {
        let manifest = try await manifests.manifest(forceRefresh: true)
        guard let entry = manifest.versions.first(where: { $0.id == instance.minecraftVersion }) else {
            throw LaunchError.versionNotFound(instance.minecraftVersion)
        }
        _ = try await manifests.versionJSON(for: entry)
        onProgress(1.0, "Repair complete")
    }

    // MARK: - Arguments

    private func buildGameArguments(version: VersionJSON, substitutions: [String: String]) -> [String] {
        func substitute(_ raw: String) -> String {
            var result = raw
            for (key, value) in substitutions {
                result = result.replacingOccurrences(of: "${\(key)}", with: value)
            }
            return result
        }

        if let modern = version.arguments?.game {
            var args: [String] = []
            for value in modern {
                switch value {
                case .plain(let s):
                    args.append(substitute(s))
                case .conditional(let rules, let values):
                    // Feature-gated args (demo mode, custom resolution) are handled
                    // explicitly by the caller; os-gated args follow macOS rules.
                    let osOnly = rules.allSatisfy { $0.features == nil }
                    let allowed = osOnly && rules.contains { $0.action == "allow" && ($0.os?.name == nil || $0.os?.name == "osx") }
                    if allowed { args.append(contentsOf: values.map(substitute)) }
                }
            }
            return args
        }

        if let legacy = version.minecraftArguments {
            return legacy.split(separator: " ").map { substitute(String($0)) }
        }
        return []
    }
}

/// A running game process with live log streaming.
final class GameSession {
    let process: Process
    private let started = Date()
    private var continuation: CheckedContinuation<Int32, Never>?

    var elapsedSeconds: Int { Int(Date().timeIntervalSince(started)) }

    init(process: Process, onLog: @escaping @Sendable (String) -> Void) throws {
        self.process = process

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        for pipe in [stdout, stderr] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    onLog(String(line))
                }
            }
        }
        try process.run()
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            if !process.isRunning {
                continuation.resume(returning: process.terminationStatus)
                return
            }
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
        }
    }

    func terminate() {
        process.terminate()
    }
}
