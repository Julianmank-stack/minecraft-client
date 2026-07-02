import Foundation

/// Patches Minecraft's options.txt before launch — currently the maxFps line,
/// used by the FPS cap and Thermal Guard features.
///
/// Thermal Guard writes are temporary: the previous value is saved next to
/// options.txt and restored on the next launch where the guard doesn't fire,
/// so a hot afternoon never permanently changes the player's settings.
enum OptionsPatcher {
    struct Patch {
        /// Desired maxFps value (nil = no explicit cap).
        let fpsCap: Int?
        /// True when Thermal Guard forced this cap (restore later).
        let temporary: Bool
    }

    private static let backupName = ".metalcraft-maxfps-backup"

    /// Returns a human-readable description of what was done (for the log).
    @discardableResult
    static func apply(_ patch: Patch, gameDir: URL) throws -> String {
        let optionsURL = gameDir.appendingPathComponent("options.txt")
        let backupURL = gameDir.appendingPathComponent(backupName)
        let fm = FileManager.default

        var lines = (try? String(contentsOf: optionsURL, encoding: .utf8))?
            .components(separatedBy: "\n") ?? []
        let currentValue = lines.first { $0.hasPrefix("maxFps:") }?
            .dropFirst("maxFps:".count).trimmingCharacters(in: .whitespaces)

        func write(maxFps: String?) throws {
            lines.removeAll { $0.hasPrefix("maxFps:") }
            if let maxFps {
                lines.append("maxFps:\(maxFps)")
            }
            let text = lines.filter { !$0.isEmpty }.joined(separator: "\n") + "\n"
            try fm.createDirectory(at: gameDir, withIntermediateDirectories: true)
            try text.write(to: optionsURL, atomically: true, encoding: .utf8)
        }

        if let cap = patch.fpsCap, patch.temporary {
            // Thermal Guard: remember what the player had, then cap.
            if !fm.fileExists(atPath: backupURL.path) {
                try (currentValue ?? "absent").write(to: backupURL, atomically: true, encoding: .utf8)
            }
            try write(maxFps: String(cap))
            return "Thermal Guard capped frame rate at \(cap) FPS (previous setting will be restored)"
        }

        if let cap = patch.fpsCap {
            // Explicit user cap: authoritative, drop any pending restore.
            try? fm.removeItem(at: backupURL)
            try write(maxFps: String(cap))
            return "Frame rate capped at \(cap) FPS"
        }

        // No cap requested: restore a Thermal Guard backup if one is pending.
        if let saved = try? String(contentsOf: backupURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) {
            try write(maxFps: saved == "absent" ? nil : saved)
            try? fm.removeItem(at: backupURL)
            return "Restored frame-rate setting after Thermal Guard (\(saved == "absent" ? "default" : saved))"
        }
        return "Frame rate left untouched"
    }
}
