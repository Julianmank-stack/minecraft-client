import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeStore
    @AppStorage("defaultRamMB") private var defaultRamMB = 4096
    @AppStorage("notifyLaunchReady") private var notifyLaunchReady = true
    @AppStorage("notifyCrashes") private var notifyCrashes = true
    @AppStorage("msaClientID") private var msaClientID = ""

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Mode", selection: $theme.appearance) {
                    Text("System").tag("system")
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Color scheme")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        ForEach(ThemeScheme.allCases) { scheme in
                            SchemeSwatch(
                                scheme: scheme,
                                isSelected: theme.scheme == scheme,
                                customHex: theme.customAccentHex
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    theme.scheme = scheme
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                if theme.scheme == .custom {
                    ColorPicker("Custom accent color", selection: Binding(
                        get: { Color(hex: theme.customAccentHex) },
                        set: { theme.customAccentHex = $0.hexString }
                    ), supportsOpacity: false)
                }

                Toggle("Fun effects (aurora glow, pixel particles, button pulse)", isOn: $theme.funEffects)
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
                TextField("Custom Azure client ID (optional)", text: $msaClientID,
                          prompt: Text("Leave empty to use the built-in Microsoft sign-in"))
                Text("Advanced: only needed if you registered your own Azure AD app (see docs/AZURE_APP_SETUP.md). Takes effect on the next sign-in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

/// A clickable gradient swatch previewing one color scheme.
private struct SchemeSwatch: View {
    let scheme: ThemeScheme
    let isSelected: Bool
    let customHex: String
    let action: () -> Void

    var body: some View {
        let palette = ThemeStore.palette(for: scheme, customHex: customHex)
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.gradient)
                    .frame(height: 34)
                    .overlay {
                        if scheme == .custom {
                            Image(systemName: "paintpalette")
                                .foregroundStyle(.white)
                                .font(.caption)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? palette.accent : .clear, lineWidth: 2.5)
                            .padding(-3)
                    )
                Text(scheme.displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .hoverLift(scale: 1.05)
    }
}
