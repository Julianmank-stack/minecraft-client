import SwiftUI

/// Modrinth browser for mods, modpacks, shaders and resource packs.
struct ModrinthBrowserView: View {
    @EnvironmentObject private var appState: AppState
    let projectType: ModrinthAPI.ProjectType

    @State private var query = ""
    @State private var hits: [ModrinthAPI.SearchHit] = []
    @State private var isLoading = false
    @State private var selectedType: ModrinthAPI.ProjectType
    @State private var searchTask: Task<Void, Never>?
    @State private var installMessage: String?

    init(projectType: ModrinthAPI.ProjectType) {
        self.projectType = projectType
        _selectedType = State(initialValue: projectType)
    }

    var body: some View {
        VStack(spacing: 0) {
            picker
            if isLoading && hits.isEmpty {
                Spacer()
                ProgressView("Searching Modrinth…")
                Spacer()
            } else {
                list
            }
            if let installMessage {
                Text(installMessage)
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }
        }
        .searchable(text: $query, prompt: "Search Modrinth")
        .onChange(of: query) { scheduleSearch() }
        .onChange(of: selectedType) { scheduleSearch(immediate: true) }
        .task { scheduleSearch(immediate: true) }
        .navigationTitle("Browse")
    }

    private var picker: some View {
        Picker("Type", selection: $selectedType) {
            Text("Mods").tag(ModrinthAPI.ProjectType.mod)
            Text("Modpacks").tag(ModrinthAPI.ProjectType.modpack)
            Text("Shaders").tag(ModrinthAPI.ProjectType.shader)
            Text("Resource Packs").tag(ModrinthAPI.ProjectType.resourcepack)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(16)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(hits) { hit in
                    GlassCard(padding: 12) {
                        HStack(spacing: 12) {
                            AsyncImage(url: hit.iconUrl.flatMap(URL.init(string:))) { image in
                                image.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                PixelBlockIcon(seedText: hit.title, size: 44)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(hit.title).font(.headline)
                                Text(hit.description)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack(spacing: 8) {
                                    Label("\(hit.downloads.formatted(.number.notation(.compactName)))", systemImage: "arrow.down.circle")
                                    Text("by \(hit.author)")
                                }
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Install") {
                                Task { await install(hit) }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedType != .modpack && appState.selectedInstance == nil)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func scheduleSearch(immediate: Bool = false) {
        searchTask?.cancel()
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(for: .milliseconds(300))   // debounce
                guard !Task.isCancelled else { return }
            }
            isLoading = true
            defer { isLoading = false }
            if let response = try? await appState.modrinth.search(query: query, type: selectedType) {
                hits = response.hits
            }
        }
    }

    /// Modpacks → new instance via MrPackInstaller.
    /// Mods/shaders/packs → download into the selected instance's folders,
    /// resolving required dependencies.
    private func install(_ hit: ModrinthAPI.SearchHit) async {
        installMessage = "Installing \(hit.title)…"
        defer {
            Task {
                try? await Task.sleep(for: .seconds(4))
                installMessage = nil
            }
        }
        do {
            if selectedType == .modpack {
                guard let version = try await appState.modrinth.versions(projectId: hit.projectId).first,
                      let file = version.files.first(where: \.primary) ?? version.files.first,
                      let url = URL(string: file.url) else { return }
                let (temp, _) = try await URLSession.shared.download(from: url)
                let mrpack = temp.deletingLastPathComponent().appendingPathComponent(file.filename)
                try? FileManager.default.removeItem(at: mrpack)
                try FileManager.default.moveItem(at: temp, to: mrpack)

                let installer = MrPackInstaller(instanceStore: appState.instanceStore)
                let instance = try await installer.install(
                    mrpackAt: mrpack,
                    modrinthLink: .init(projectId: hit.projectId, versionId: version.id)
                ) { _, detail in
                    Task { @MainActor in installMessage = detail }
                }
                appState.instances = (try? appState.instanceStore.loadAll()) ?? []
                appState.selectedInstanceID = instance.id
                installMessage = "Installed \(hit.title)"
            } else {
                guard let instance = appState.selectedInstance else { return }
                let subdir = switch selectedType {
                case .mod: "mods"
                case .shader: "shaderpacks"
                case .resourcepack: "resourcepacks"
                case .modpack: "mods"
                }
                let versions = try await appState.modrinth.versions(
                    projectId: hit.projectId,
                    minecraftVersion: instance.minecraftVersion,
                    loader: selectedType == .mod ? instance.loader.type : nil
                )
                guard let version = versions.first else {
                    installMessage = "No compatible version for \(instance.minecraftVersion)"
                    return
                }
                var toInstall = [version]
                if selectedType == .mod {
                    toInstall += try await appState.modrinth.resolveDependencies(
                        of: version,
                        minecraftVersion: instance.minecraftVersion,
                        loader: instance.loader.type
                    )
                }
                let downloads = DownloadManager()
                var items: [DownloadManager.Item] = []
                for v in toInstall {
                    guard let file = v.files.first(where: \.primary) ?? v.files.first,
                          let url = URL(string: file.url) else { continue }
                    items.append(.init(
                        url: url,
                        destination: instance.gameDir.appendingPathComponent("\(subdir)/\(file.filename)"),
                        sha1: file.hashes.sha1,
                        size: file.size
                    ))
                }
                try await downloads.download(items) { _, _ in }
                installMessage = "Installed \(hit.title)" + (toInstall.count > 1 ? " (+\(toInstall.count - 1) dependencies)" : "")
            }
        } catch {
            installMessage = "Install failed: \(error.localizedDescription)"
        }
    }
}
