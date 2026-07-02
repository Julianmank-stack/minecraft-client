import SwiftUI
import UniformTypeIdentifiers

struct InstancesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var filtered: [Instance] {
        guard !searchText.isEmpty else { return appState.instances }
        return appState.instances.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                ForEach(filtered) { instance in
                    LargeInstanceCard(instance: instance)
                }
                newInstanceCard
            }
            .padding(24)
        }
        .searchable(text: $searchText, prompt: "Search instances")
        .navigationTitle("Instances")
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var newInstanceCard: some View {
        Button { appState.presentNewInstance = true } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
                Text("New Instance")
                    .font(.callout.weight(.medium))
                Text("or drop a .mrpack / Prism folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(.tertiary)
            )
        }
        .buttonStyle(.plain)
    }

    /// Drag-and-drop: .mrpack files → Modrinth import; folders → Prism import.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.pathExtension == "mrpack" {
                        let installer = MrPackInstaller(instanceStore: appState.instanceStore)
                        if let instance = try? await installer.install(mrpackAt: url, onProgress: { _, _ in }) {
                            appState.instances = (try? appState.instanceStore.loadAll()) ?? appState.instances
                            appState.selectedInstanceID = instance.id
                        }
                    } else {
                        let importer = PrismImporter(instanceStore: appState.instanceStore)
                        if let candidate = try? importer.inspect(folder: url),
                           let instance = try? importer.importInstance(candidate, onProgress: { _, _ in }) {
                            appState.instances = (try? appState.instanceStore.loadAll()) ?? appState.instances
                            appState.selectedInstanceID = instance.id
                        }
                    }
                }
            }
        }
        return true
    }
}

struct LargeInstanceCard: View {
    @EnvironmentObject private var appState: AppState
    let instance: Instance

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    PixelBlockIcon(seedText: instance.name, size: 48)
                    Spacer()
                    Menu {
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
                        Button("Duplicate") {
                            _ = try? appState.instanceStore.duplicate(instance, newName: instance.name + " copy")
                            appState.instances = (try? appState.instanceStore.loadAll()) ?? []
                        }
                        Button("Repair Instance") {
                            Task {
                                try? await appState.launchEngine.repair(instance: instance) { _, _ in }
                            }
                        }
                        Divider()
                        Button("Move to Trash", role: .destructive) {
                            try? appState.instanceStore.delete(instance.id)
                            appState.instances = (try? appState.instanceStore.loadAll()) ?? []
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }
                Text(instance.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    chip(instance.minecraftVersion)
                    chip(instance.loader.type.displayName)
                }
                if let lastPlayed = instance.lastPlayed {
                    Text("Played \(lastPlayed.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .hoverLift()
        .onTapGesture { appState.selectedInstanceID = instance.id }
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

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary))
    }
}

/// Sheet for creating a fresh instance.
struct NewInstanceSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var version = "1.21.4"
    @State private var loaderType: LoaderType = .vanilla
    @State private var availableVersions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Instance")
                .font(.title2.weight(.bold))

            Form {
                TextField("Name", text: $name)
                Picker("Minecraft version", selection: $version) {
                    ForEach(availableVersions.isEmpty ? [version] : availableVersions, id: \.self) {
                        Text($0)
                    }
                }
                Picker("Loader", selection: $loaderType) {
                    ForEach(LoaderType.allCases) { Text($0.displayName).tag($0) }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    let instance = try? appState.instanceStore.create(
                        name: name.isEmpty ? "Minecraft \(version)" : name,
                        minecraftVersion: version,
                        loader: .init(type: loaderType, version: nil)
                    )
                    appState.instances = (try? appState.instanceStore.loadAll()) ?? []
                    appState.selectedInstanceID = instance?.id
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
        .task {
            let service = VersionManifestService()
            if let manifest = try? await service.manifest() {
                availableVersions = manifest.versions
                    .filter { $0.type == "release" }
                    .map(\.id)
                version = manifest.latest.release
            }
        }
    }
}
