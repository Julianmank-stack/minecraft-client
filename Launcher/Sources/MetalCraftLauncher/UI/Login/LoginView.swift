import SwiftUI

/// Microsoft device-code sign-in sheet. The password is typed on microsoft.com
/// in the user's browser — never in this app.
struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.dismiss) private var dismiss

    @State private var deviceCode: MicrosoftAuthService.DeviceCode?
    @State private var errorMessage: String?
    @State private var isPolling = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 44))
                .gradientForeground(theme.palette)
                .glowPulse(theme.palette.accent, enabled: theme.funEffects)

            Text("Sign in to Minecraft")
                .font(.system(.title2, design: .rounded).weight(.bold))

            if let deviceCode {
                VStack(spacing: 12) {
                    Text("Enter this code at \(URL(string: deviceCode.verificationUri)?.host ?? "microsoft.com")")
                        .foregroundStyle(.secondary)
                    Text(deviceCode.userCode)
                        .font(.system(size: 34, design: .monospaced).weight(.bold))
                        .kerning(4)
                        .textSelection(.enabled)
                    Button("Copy Code & Open Browser") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(deviceCode.userCode, forType: .string)
                        if let url = URL(string: deviceCode.verificationUri) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if isPolling {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for you to finish in the browser…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Button {
                    Task { await startSignIn() }
                } label: {
                    Label("Sign in with Microsoft", systemImage: "person.badge.key")
                        .frame(width: 240)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Text("Official Microsoft sign-in only. Your password never touches this app.\nTokens are stored in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if appState.account != nil {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(36)
        .frame(width: 420)
    }

    private func startSignIn() async {
        errorMessage = nil
        do {
            let code = try await appState.auth.requestDeviceCode()
            deviceCode = code
            isPolling = true
            let account = try await appState.auth.completeSignIn(deviceCode: code)
            appState.account = account
            isPolling = false
            dismiss()
        } catch {
            isPolling = false
            deviceCode = nil
            errorMessage = error.localizedDescription
        }
    }
}
