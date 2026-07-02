import Foundation
import AppKit

/// What kind of instance content a customize view is editing.
enum ContentKind: String, CaseIterable, Identifiable {
    case mods, resourcepacks, shaderpacks

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mods: "Mods"
        case .resourcepacks: "Resource Packs"
        case .shaderpacks: "Shaders"
        }
    }

    var folderName: String { rawValue }

    /// File extensions accepted when adding files of this kind.
    var fileExtensions: [String] {
        switch self {
        case .mods: ["jar"]
        case .resourcepacks, .shaderpacks: ["zip"]
        }
    }

    /// Only mods support the .disabled rename convention (loaders skip
    /// non-.jar files; packs are toggled in-game instead).
    var supportsDisabling: Bool { self == .mods }
}

struct ContentFile: Identifiable, Equatable {
    let url: URL
    let kind: ContentKind

    var id: String { url.path }

    var isDisabled: Bool { url.lastPathComponent.hasSuffix(".disabled") }

    /// Display name without .jar/.zip/.disabled noise.
    var displayName: String {
        var name = url.lastPathComponent
        if name.hasSuffix(".disabled") { name = String(name.dropLast(".disabled".count)) }
        return name
    }

    var sizeBytes: Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }
}

/// File operations behind the instance Customize sheet: list, enable/disable,
/// delete, and add mods / resource packs / shaders. Works identically for
/// created, Modrinth-installed, and Prism-imported instances — the game dir
/// is always the source of truth.
final class InstanceContentManager {
    private let fm = FileManager.default

    func folder(for instance: Instance, kind: ContentKind) -> URL {
        instance.gameDir.appendingPathComponent(kind.folderName, isDirectory: true)
    }

    func files(in instance: Instance, kind: ContentKind) -> [ContentFile] {
        let dir = folder(for: instance, kind: kind)
        guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }
        return contents
            .filter { url in
                let name = url.lastPathComponent.lowercased()
                return kind.fileExtensions.contains { name.hasSuffix(".\($0)") || name.hasSuffix(".\($0).disabled") }
            }
            .map { ContentFile(url: $0, kind: kind) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Enable ⇄ disable by renaming file.jar ⇄ file.jar.disabled.
    @discardableResult
    func toggle(_ file: ContentFile) throws -> ContentFile {
        guard file.kind.supportsDisabling else { return file }
        let target: URL = file.isDisabled
            ? file.url.deletingPathExtension()                       // strip .disabled
            : file.url.appendingPathExtension("disabled")
        try fm.moveItem(at: file.url, to: target)
        return ContentFile(url: target, kind: file.kind)
    }

    /// Delete moves to Trash, matching macOS expectations.
    func delete(_ file: ContentFile) throws {
        try fm.trashItem(at: file.url, resultingItemURL: nil)
    }

    /// Copy files in (from an open panel or drag-and-drop). Returns how many
    /// were accepted; files with the wrong extension are skipped.
    @discardableResult
    func add(_ urls: [URL], to instance: Instance, kind: ContentKind) throws -> Int {
        let dir = folder(for: instance, kind: kind)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var added = 0
        for url in urls where kind.fileExtensions.contains(url.pathExtension.lowercased()) {
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: url, to: dest)
            added += 1
        }
        return added
    }

    func revealInFinder(_ instance: Instance, kind: ContentKind) {
        let dir = folder(for: instance, kind: kind)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
