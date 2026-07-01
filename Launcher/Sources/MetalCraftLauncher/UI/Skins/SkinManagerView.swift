import SwiftUI
import UniformTypeIdentifiers

struct SkinManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var library: [SkinManager.LibrarySkin] = []
    @State private var message: String?

    var body: some View {
        HSplitView {
            currentSkinPanel
                .frame(minWidth: 280)
            libraryPanel
                .frame(minWidth: 380)
        }
        .navigationTitle("Skins")
        .task { library = appState.skins.library() }
    }

    private var currentSkinPanel: some View {
        VStack(spacing: 16) {
            Text("Current Skin").font(.headline)

            if let account = appState.account {
                // 3D preview slot: SceneKit player model fed by the skin texture.
                // The placeholder shows the identity block-avatar until textures load.
                PlayerAvatarView(account: account, size: 160)
                    .shadow(radius: 8)

                VStack(spacing: 4) {
                    Text(account.username).font(.title3.weight(.semibold))
                    Text(account.uuid)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text(account.skinModel == .slim ? "Slim model" : "Classic model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if account.capeURL != nil {
                        Label("Cape equipped", systemImage: "flag.fill")
                            .font(.caption)
                            .foregroundStyle(.purple)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Sign in to manage skins",
                    systemImage: "person.crop.square.badge.camera",
                    description: Text("Your current skin and cape appear here.")
                )
            }
            Spacer()
        }
        .padding(20)
    }

    private var libraryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Skin Library").font(.headline)
                Spacer()
                Button("Add Skin…") { pickSkin() }
            }

            if library.isEmpty {
                ContentUnavailableView(
                    "No saved skins",
                    systemImage: "square.grid.2x2",
                    description: Text("Add PNG skins (64×64 or legacy 64×32) to keep a local library.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                        ForEach(library) { skin in
                            GlassCard(padding: 10) {
                                VStack(spacing: 6) {
                                    PixelBlockIcon(seedText: skin.name, size: 64)
                                    Text(skin.name).font(.callout).lineLimit(1)
                                    Text(skin.model == .slim ? "Slim" : "Classic")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Button("Apply") { Task { await apply(skin) } }
                                        .controlSize(.small)
                                        .disabled(appState.account == nil)
                                }
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    try? appState.skins.removeFromLibrary(skin)
                                    library = appState.skins.library()
                                }
                            }
                        }
                    }
                }
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private func pickSkin() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try appState.skins.addToLibrary(
                skinAt: url,
                name: url.deletingPathExtension().lastPathComponent,
                model: .classic
            )
            library = appState.skins.library()
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func apply(_ skin: SkinManager.LibrarySkin) async {
        guard let account = appState.account else { return }
        do {
            let token = try await appState.auth.minecraftToken(for: account)
            let file = Paths.skins.appendingPathComponent(skin.file)
            try await appState.skins.upload(skinAt: file, model: skin.model, accessToken: token)
            message = "Skin \"\(skin.name)\" applied."
            appState.account = try? await appState.auth.restoreSession()
        } catch {
            message = "Couldn't apply skin: \(error.localizedDescription)"
        }
    }
}
