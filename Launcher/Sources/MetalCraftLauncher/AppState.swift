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

    var selectedInstance: Instance? {
        instances.first { $0.id == selectedInstanceID } ?? instances.first
    }

    func bootstrap() async {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
        }
        do {
            try Paths.ensureDirectories()
            instances = try instanceStore.loadAll()
            selectedInstanceID = instances.first?.id
            servers = (try? serverStore.load()) ?? []
            account = try? await auth.restoreSession()
            presentLogin = (account == nil)
        } catch {
            liveLogLines.append(.launcher("Bootstrap failed: \(error.localizedDescription)"))
        }
    }

    func launchSelectedInstance() async {
        guard let instance = selectedInstance else { return }
        guard let account else { presentLogin = true; return }

        // FPS cap + Thermal Guard: tighten the cap when macOS already reports
        // thermal pressure, so a hot chassis doesn't throttle mid-game.
        let guardOn = instance.thermalGuard ?? true
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
                Task { @MainActor in self?.liveLogLines.append(.game(line)) }
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
