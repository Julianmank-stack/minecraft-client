import Foundation

/// Runs before/after benchmarks by launching the instance with
/// metalcraft.benchmark=true; the engine mod loads a deterministic scene,
/// records frame times for 60s, writes results, and exits.
final class BenchmarkRunner {
    struct Result: Codable, Identifiable {
        var id: String { "\(instance)-\(date.timeIntervalSince1970)" }
        let instance: UUID
        let date: Date
        let mode: RendererMode
        let durationSeconds: Int
        let avgFPS: Double
        let onePercentLowFPS: Double
        let avgFrameTimeMs: Double
        let maxMemoryMB: Int
        let scene: String
    }

    enum BenchmarkError: LocalizedError {
        case engineModRequired
        case noResultProduced

        var errorDescription: String? {
            switch self {
            case .engineModRequired: "Benchmarking needs the MetalCraft Engine mod (Fabric or Quilt instances)."
            case .noResultProduced: "The benchmark run didn't produce a result file."
            }
        }
    }

    private var resultsDir: URL { Paths.meta.appendingPathComponent("benchmarks", isDirectory: true) }

    /// Launch a benchmark run and collect the result written by the engine mod.
    func run(
        instance: Instance,
        account: MinecraftAccount,
        launchEngine: LaunchEngine,
        rendererConfig: RendererManager.EngineConfig,
        onProgress: @escaping @Sendable (Double, String) -> Void
    ) async throws -> Result {
        guard instance.loader.type.supportsMetalCraftEngine else { throw BenchmarkError.engineModRequired }

        var benchmarkInstance = instance
        benchmarkInstance.jvmArgs.append("-Dmetalcraft.benchmark=true")

        let session = try await launchEngine.launch(
            instance: benchmarkInstance,
            account: account,
            rendererConfig: rendererConfig,
            accessTokenOverride: "0",   // benchmark scene is fully offline
            onProgress: onProgress,
            onLog: { _ in }
        )
        _ = await session.waitForExit()

        // The mod writes logs/renderer/benchmark-<ts>.json
        let rendererLogs = Paths.rendererLogDir(instance.id)
        guard let newest = (try? FileManager.default.contentsOfDirectory(
                at: rendererLogs, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter({ $0.lastPathComponent.hasPrefix("benchmark-") && $0.pathExtension == "json" })
            .max(by: { modified($0) < modified($1) }),
              let data = try? Data(contentsOf: newest) else {
            throw BenchmarkError.noResultProduced
        }

        struct ModResult: Decodable {
            let durationSeconds: Int
            let avgFPS: Double
            let onePercentLowFPS: Double
            let avgFrameTimeMs: Double
            let maxMemoryMB: Int
            let scene: String
        }
        let modResult = try JSONDecoder().decode(ModResult.self, from: data)

        let result = Result(
            instance: instance.id,
            date: Date(),
            mode: instance.renderer.mode,
            durationSeconds: modResult.durationSeconds,
            avgFPS: modResult.avgFPS,
            onePercentLowFPS: modResult.onePercentLowFPS,
            avgFrameTimeMs: modResult.avgFrameTimeMs,
            maxMemoryMB: modResult.maxMemoryMB,
            scene: modResult.scene
        )
        try persist(result)
        return result
    }

    /// Latest result per renderer mode, for before/after comparison bars.
    func history(for instance: UUID) -> [Result] {
        let dir = resultsDir.appendingPathComponent(instance.uuidString)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.compactMap { try? decoder.decode(Result.self, from: Data(contentsOf: $0)) }
            .sorted { $0.date > $1.date }
    }

    private func persist(_ result: Result) throws {
        let dir = resultsDir.appendingPathComponent(result.instance.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result)
            .write(to: dir.appendingPathComponent("\(Int(result.date.timeIntervalSince1970)).json"), options: .atomic)
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
