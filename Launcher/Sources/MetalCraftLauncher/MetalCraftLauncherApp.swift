import SwiftUI

@main
struct MetalCraftLauncherApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 640)
                .task { await appState.bootstrap() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Instance") { appState.presentNewInstance = true }
                    .keyboardShortcut("n")
            }
            CommandMenu("Play") {
                Button("Launch Selected Instance") {
                    Task { await appState.launchSelectedInstance() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(appState.selectedInstance == nil)

                Button("Show Live Log") { appState.selectedSection = .logs }
                    .keyboardShortcut("l")
            }
            CommandGroup(after: .toolbar) {
                ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                    Button(section.title) { appState.selectedSection = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
        }

        Settings {
            SettingsView().environmentObject(appState)
        }
    }
}
