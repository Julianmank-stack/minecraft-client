import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
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
        .preferredColorScheme(nil)   // follow system; dark-mode-first design
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
