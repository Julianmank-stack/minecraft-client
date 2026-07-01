import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("theme") private var theme = "system"
    @AppStorage("defaultRamMB") private var defaultRamMB = 4096
    @AppStorage("notifyLaunchReady") private var notifyLaunchReady = true
    @AppStorage("notifyCrashes") private var notifyCrashes = true

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
            }

            Section("Defaults") {
                Stepper("Default RAM: \(defaultRamMB / 1024) GB",
                        value: $defaultRamMB, in: 1024...32768, step: 1024)
            }

            Section("Notifications") {
                Toggle("Ready to play", isOn: $notifyLaunchReady)
                Toggle("Crash alerts", isOn: $notifyCrashes)
            }

            Section("Account") {
                if let account = appState.account {
                    LabeledContent("Signed in as", value: account.username)
                    Button("Sign Out", role: .destructive) {
                        appState.auth.signOut(account)
                        appState.account = nil
                    }
                } else {
                    Button("Sign In…") { appState.presentLogin = true }
                }
            }

            Section("Storage") {
                LabeledContent("Data folder", value: Paths.root.path)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.root])
                }
            }

            Section("Import") {
                Button("Import Prism Launcher instances…") {
                    // Detection runs against the standard Prism locations;
                    // results appear as import candidates.
                    let importer = PrismImporter(instanceStore: appState.instanceStore)
                    for candidate in importer.detect() {
                        _ = try? importer.importInstance(candidate) { _, _ in }
                    }
                    appState.instances = (try? appState.instanceStore.loadAll()) ?? []
                }
            }

            Section("About") {
                LabeledContent("Hardware", value: appState.hardware.cpuName)
                LabeledContent("GPU", value: appState.hardware.gpuName)
                LabeledContent("Metal 3", value: appState.hardware.supportsMetal3 ? "Supported" : "Not supported")
                LabeledContent("Unified memory", value: appState.hardware.hasUnifiedMemory ? "Yes" : "No")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
