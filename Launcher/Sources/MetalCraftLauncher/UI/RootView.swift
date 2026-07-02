import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    ZStack {
                        Color(nsColor: .windowBackgroundColor)
                        // Ambient animation pauses while the game runs so the
                        // launcher takes zero GPU/CPU away from Minecraft.
                        if theme.funEffects && !appState.launchState.isBusy {
                            AuroraBackground(palette: theme.palette)
                        }
                    }
                    .ignoresSafeArea()
                }
        }
        .sheet(isPresented: $appState.presentLogin) {
            LoginView()
        }
        .sheet(isPresented: $appState.presentNewInstance) {
            NewInstanceSheet()
        }
        .sheet(item: $appState.customizingInstance) { instance in
            CustomizeInstanceSheet(instance: instance)
        }
        .tint(theme.palette.accent)
        .accentColor(theme.palette.accent)
        .preferredColorScheme(theme.preferredColorScheme)
        .animation(.easeInOut(duration: 0.4), value: theme.scheme)
    }

    @ViewBuilder
    private var content: some View {
        switch appState.selectedSection {
        case .home:
            DashboardView()
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        case .instances: InstancesView()
        case .mods: ModrinthBrowserView(projectType: .mod)
        case .skins: SkinManagerView()
        case .servers: ServerManagerView()
        case .optimize: OptimizationCenterView()
        case .logs: LogsView()
        case .settings: SettingsView()
        }
    }
}
