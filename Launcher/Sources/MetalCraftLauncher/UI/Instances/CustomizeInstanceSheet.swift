import SwiftUI
import UniformTypeIdentifiers

/// Right-click → Customize on an instance. Edit its mods (enable/disable,
/// delete, add), resource packs, and shaders. Files can also be dropped
/// straight onto the sheet.
struct CustomizeInstanceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let instance: Instance
    private let manager = InstanceContentManager()

    @State private var kind: ContentKind = .mods
    @State private var files: [ContentFile] = []
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            picker
            content
            footer
        }
        .frame(width: 560, height: 480)
        .onAppear { reload() }
        .onChange(of: kind) { reload() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            PixelBlockIcon(seedText: instance.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Customize \(instance.name)")
                    .font(.title3.weight(.semibold))
                Text("\(instance.minecraftVersion) · \(instance.loader.type.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                manager.revealInFinder(instance, kind: kind)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        .padding(16)
    }

    private var picker: some View {
        Picker("Kind", selection: $kind) {
            ForEach(ContentKind.allCases) { Text($0.displayName).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var content: some View {
        if files.isEmpty {
            ContentUnavailableView {
                Label("No \(kind.displayName.lowercased()) yet", systemImage: "puzzlepiece.extension")
            } description: {
                Text("Add files below, drop them here, or install from the Mods tab (Modrinth).")
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(files) { file in
                    row(file)
                }
            }
            .listStyle(.inset)
        }
    }

    private func row(_ file: ContentFile) -> some View {
        HStack(spacing: 10) {
            if kind.supportsDisabling {
                Toggle("", isOn: Binding(
                    get: { !file.isDisabled },
                    set: { _ in toggle(file) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayName)
                    .font(.callout)
                    .foregroundStyle(file.isDisabled ? .secondary : .primary)
                    .strikethrough(file.isDisabled, color: .secondary)
                Text(ByteCountFormatter.string(fromByteCount: Int64(file.sizeBytes), countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if file.isDisabled {
                Text("Disabled")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Button {
                delete(file)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Move to Trash")
        }
        .contextMenu {
            if kind.supportsDisabling {
                Button(file.isDisabled ? "Enable" : "Disable") { toggle(file) }
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            }
            Divider()
            Button("Move to Trash", role: .destructive) { delete(file) }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                addFiles()
            } label: {
                Label("Add \(kind.displayName)…", systemImage: "plus")
            }
            Text("or drop files anywhere on this window")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
        }
        .padding(16)
    }

    // MARK: - Actions

    private func reload() {
        files = manager.files(in: instance, kind: kind)
    }

    private func toggle(_ file: ContentFile) {
        do {
            try manager.toggle(file)
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete(_ file: ContentFile) {
        do {
            try manager.delete(file)
            reload()
        } catch {
            message = error.localizedDescription
        }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = kind.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        importFiles(panel.urls)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in importFiles([url]) }
            }
        }
        return true
    }

    private func importFiles(_ urls: [URL]) {
        do {
            let added = try manager.add(urls, to: instance, kind: kind)
            let skipped = urls.count - added
            message = skipped > 0
                ? "Added \(added), skipped \(skipped) (wrong file type)"
                : "Added \(added) file\(added == 1 ? "" : "s")"
            reload()
        } catch {
            message = error.localizedDescription
        }
    }
}
