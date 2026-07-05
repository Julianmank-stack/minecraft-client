import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case home, instances, mods, skins, servers, optimize, logs, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .instances: "Instances"
        case .mods: "Mods"
        case .skins: "Skins"
        case .servers: "Servers"
        case .optimize: "Optimize"
        case .logs: "Logs"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "play.house"
        case .instances: "square.grid.2x2"
        case .mods: "puzzlepiece.extension"
        case .skins: "person.crop.square"
        case .servers: "network"
        case .optimize: "bolt"
        case .logs: "text.alignleft"
        case .settings: "gearshape"
        }
    }
}

/// Central observable state. UI views read this; services mutate it on the main actor.
@MainActor
final class AppState: ObservableObject {
    // Navigation
    @Published var selectedSection: SidebarSection = .home
    @Published var presentNewInstance = false
    @Published var presentLogin = false
    @Published var customizingInstance: Instance?

    // Data
    @Published var account: MinecraftAccount?
    @Published var instances: [Instance] = []
    @Published var selectedInstanceID: Instance.ID?
    @Published var servers: [ServerEntry] = []

    // Runtime
    @Published var launchState: LaunchState = .idle
    @Published var liveLogLines: [LogLine] = []
    @Published var lastCrashDiagnosis: CrashDiagnosis?
    @Published var hardware: HardwareReport = .current()
    @Published var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    /// Real die temperatures (nil on Macs where the sensor interface is unavailable).
    @Published var sensorReading: ThermalSensorReader.Reading?
    /// Set when the data folder was migrated from a different Mac — instances
    /// still carry heap sizes/JVM args computed for the old hardware.
    /// Holds a description of the previous machine (e.g. "Apple M2 · 16 GB").
    @Published var previousMacDescription: String?

    // Services
    let keychain = KeychainStore()
    lazy var auth = MicrosoftAuthService(keychain: keychain)
    let instanceStore = InstanceStore()
    let javaManager = JavaRuntimeManager()
    let modrinth = ModrinthAPI()
    lazy var rendererManager = RendererManager(hardware: hardware)
    lazy var optimization = OptimizationEngine(hardware: hardware)
    lazy var launchEngine = LaunchEngine(javaManager: javaManager)
    let serverStore = ServerStore()
    let pinger = ServerPinger()
    let skins = SkinManager()
    let crashAnalyzer = CrashAnalyzer()
    private let sensorReader = ThermalSensorReader()

    var selectedInstance: Instance? {
        instances.first { $0.id == selectedInstanceID } ?? instances.first
    }

    /// Bounded log buffer: long sessions with chatty mods would otherwise grow
    /// the array (and LogsView work) without limit.
    func appendLog(_ line: LogLine) {
        liveLogLines.append(line)
        if liveLogLines.count > 2500 {
            liveLogLines.removeFirst(1000)
        }
    }

    func bootstrap() async {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
        }
        startSensorPolling()
        do {
            try Paths.ensureDirectories()
            instances = try instanceStore.loadAll()
            selectedInstanceID = instances.first?.id
            servers = (try? serverStore.load()) ?? []
            account = try? await auth.restoreSession()
            presentLogin = (account == nil)
            checkForHardwareChange()
        } catch {
            liveLogLines.append(.launcher("Bootstrap failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Hardware migration

    private struct StoredHardware: Codable {
        var physicalMemoryMB: Int
        var gpuName: String
    }

    /// Compares this Mac against the fingerprint stored in launcher.json
    /// (which migrates with the data folder). On a mismatch the dashboard
    /// offers a one-click re-tune; the fingerprint is only rewritten once the
    /// user acts, so the offer survives restarts.
    private func checkForHardwareChange() {
        let stored = (try? Data(contentsOf: Paths.launcherSettings))
            .flatMap { try? JSONDecoder().decode(StoredHardware.self, from: $0) }
        guard let stored else {
            saveHardwareFingerprint()
            return
        }
        if (stored.physicalMemoryMB != hardware.physicalMemoryMB || stored.gpuName != hardware.gpuName),
           !instances.isEmpty {
            previousMacDescription = "\(stored.gpuName) · \(stored.physicalMemoryMB / 1024) GB"
        }
    }

    private func saveHardwareFingerprint() {
        let current = StoredHardware(physicalMemoryMB: hardware.physicalMemoryMB, gpuName: hardware.gpuName)
        try? JSONEncoder().encode(current).write(to: Paths.launcherSettings)
    }

    /// Re-applies each instance's own performance profile so RAM allocation
    /// and JVM args are recomputed for this machine's hardware.
    func retuneInstancesForCurrentHardware() {
        for instance in instances {
            var updated = optimization.apply(
                profile: instance.performanceProfile, to: instance, rendererManager: rendererManager
            )
            if updated.renderer.mode == .metalExperimental {
                updated.renderer.mode = .appleSiliconMax   // never auto-enable experimental
            }
            try? instanceStore.save(updated)
        }
        instances = (try? instanceStore.loadAll()) ?? instances
        saveHardwareFingerprint()
        previousMacDescription = nil
        appendLog(.launcher(
            "Re-tuned \(instances.count) instance(s) for \(hardware.gpuName) with \(hardware.physicalMemoryMB / 1024) GB RAM"
        ))
    }

    func keepMigratedTuning() {
        saveHardwareFingerprint()
        previousMacDescription = nil
    }

    /// Polls die temperatures every 5 s. The sweep itself runs off the main
    /// actor (~1 ms); only the published value lands back here.
    private func startSensorPolling() {
        let reader = sensorReader
        Task { [weak self] in
            while !Task.isCancelled {
                let reading = await Task.detached(priority: .utility) { reader.read() }.value
                guard let self else { return }
                if reading != self.sensorReading { self.sensorReading = reading }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func launchSelectedInstance() async {
        guard let instance = selectedInstance else { return }
        guard let account else { presentLogin = true; return }

        // FPS cap + Thermal Guard: tighten the cap when macOS already reports
        // thermal pressure. Opt-in — uncapped players stay uncapped.
        let guardOn = instance.thermalGuard ?? false
        let isHot = thermalState == .serious || thermalState == .critical
        let optionsPatch: OptionsPatcher.Patch
        if guardOn && isHot {
            optionsPatch = .init(fpsCap: min(instance.fpsCap ?? 120, 120), temporary: instance.fpsCap == nil)
        } else {
            optionsPatch = .init(fpsCap: instance.fpsCap, temporary: false)
        }

        launchState = .preparing(progress: 0, detail: "Resolving version…")
        do {
            let session = try await launchEngine.launch(
                instance: instance,
                account: account,
                rendererConfig: rendererManager.engineConfig(for: instance),
                auth: auth,
                optionsPatch: optionsPatch
            ) { [weak self] progress, detail in
                Task { @MainActor in self?.launchState = .preparing(progress: progress, detail: detail) }
            } onLog: { [weak self] line in
                Task { @MainActor in self?.appendLog(.game(line)) }
            }
            launchState = .running(session)
            Notifier.post(title: "Minecraft is running", body: instance.name)

            let exit = await session.waitForExit()
            launchState = .idle
            try instanceStore.recordPlaySession(instance.id, seconds: session.elapsedSeconds)

            if exit != 0 {
                let diagnosis = await crashAnalyzer.analyze(instance: instance, exitCode: exit)
                lastCrashDiagnosis = diagnosis
                if diagnosis.isRendererCrash {
                    let fallback = rendererManager.registerCrashAndMaybeFallback(instance: instance)
                    if let fallback {
                        try instanceStore.setRendererMode(instance.id, mode: fallback)
                        instances = try instanceStore.loadAll()
                    }
                }
                Notifier.post(title: "Minecraft crashed", body: diagnosis.headline)
            }
        } catch {
            launchState = .idle
            liveLogLines.append(.launcher("Launch failed: \(error.localizedDescription)"))
            Notifier.post(title: "Launch failed", body: error.localizedDescription)
        }
    }
}

enum LaunchState {
    case idle
    case preparing(progress: Double, detail: String)
    case running(GameSession)

    var isBusy: Bool { if case .idle = self { false } else { true } }
}

struct LogLine: Identifiable {
    enum Source { case launcher, game, renderer }
    let id = UUID()
    let source: Source
    let text: String
    let date = Date()

    static func launcher(_ text: String) -> LogLine { .init(source: .launcher, text: text) }
    static func game(_ text: String) -> LogLine { .init(source: .game, text: text) }
}
