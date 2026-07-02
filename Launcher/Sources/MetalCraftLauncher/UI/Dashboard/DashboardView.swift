import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroRow
                statusStrip
                if let diagnosis = appState.lastCrashDiagnosis {
                    crashAlert(diagnosis)
                }
                recentInstances
                quickButtons
            }
            .padding(24)
        }
        .navigationTitle("Home")
    }

    // MARK: - Hero

    private var heroRow: some View {
        HStack(spacing: 20) {
            PlayButton()

            if let instance = appState.selectedInstance {
                GlassCard {
                    HStack(spacing: 14) {
                        PixelBlockIcon(seedText: instance.name, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(instance.name)
                                .font(.title3.weight(.semibold))
                            HStack(spacing: 6) {
                                Text(instance.minecraftVersion)
                                Text("·")
                                Text(instance.loader.type.displayName)
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            Text(instance.renderer.mode.displayName)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                    }
                }
            } else {
                GlassCard {
                    VStack(spacing: 8) {
                        Text("No instances yet")
                            .font(.headline)
                        Button("Create your first instance") { appState.presentNewInstance = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Status strip

    private var statusStrip: some View {
        HStack(spacing: 10) {
            StatBadge(
                icon: "cpu",
                title: "Renderer",
                value: appState.selectedInstance?.renderer.mode.displayName ?? "—"
            )
            StatBadge(
                icon: "cup.and.saucer",
                title: "Java",
                value: appState.hardware.isAppleSilicon ? "Native aarch64" : "x86_64",
                tint: .green
            )
            StatBadge(
                icon: "bolt.fill",
                title: "Optimization",
                value: appState.selectedInstance?.performanceProfile.displayName ?? "—",
                tint: .orange
            )
            StatBadge(
                icon: "display",
                title: "GPU",
                value: appState.hardware.gpuName,
                tint: .purple
            )
            Spacer()
        }
    }

    // MARK: - Crash alert

    private func crashAlert(_ diagnosis: CrashDiagnosis) -> some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(diagnosis.headline).font(.headline)
                    Text(diagnosis.detail).font(.callout).foregroundStyle(.secondary)
                    if let suggestion = diagnosis.suggestion {
                        Text(suggestion).font(.callout)
                    }
                }
                Spacer()
                Button("View Logs") { appState.selectedSection = .logs }
                Button("Dismiss") { appState.lastCrashDiagnosis = nil }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Recent instances

    private var recentInstances: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(appState.instances.prefix(6)) { instance in
                    InstanceCard(instance: instance)
                }
            }
        }
    }

    // MARK: - Quick buttons

    private var quickButtons: some View {
        HStack(spacing: 10) {
            ForEach([SidebarSection.mods, .skins, .servers, .settings, .logs], id: \.self) { section in
                Button {
                    appState.selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// The big beautiful Play button. Morphs into a progress capsule while
/// preparing and a "Running" state while the game is up.
struct PlayButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            Task { await appState.launchSelectedInstance() }
        } label: {
            Group {
                switch appState.launchState {
                case .idle:
                    Label("Play", systemImage: "play.fill")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                case .preparing(let progress, let detail):
                    VStack(spacing: 4) {
                        ProgressView(value: progress)
                            .frame(width: 120)
                        Text(detail)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                case .running:
                    Label("Running", systemImage: "checkmark.circle.fill")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 180, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: appState.launchState.isBusy
                                ? [.gray.opacity(0.7), .gray]
                                : [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.launchState.isBusy || appState.selectedInstance == nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.launchState.isBusy)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

struct InstanceCard: View {
    @EnvironmentObject private var appState: AppState
    let instance: Instance

    var body: some View {
        GlassCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                PixelBlockIcon(seedText: instance.name, size: 40)
                Text(instance.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(instance.minecraftVersion)
                    Text("·")
                    Text(instance.loader.type.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onTapGesture {
            appState.selectedInstanceID = instance.id
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(appState.selectedInstanceID == instance.id ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contextMenu {
            Button("Launch") {
                appState.selectedInstanceID = instance.id
                Task { await appState.launchSelectedInstance() }
            }
            Button("Customize (Mods, Packs, Shaders)…") {
                appState.customizingInstance = instance
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([instance.dir])
            }
        }
    }
}
