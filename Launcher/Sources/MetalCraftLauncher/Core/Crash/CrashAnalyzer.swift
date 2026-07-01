import Foundation

struct CrashDiagnosis {
    let headline: String
    let detail: String
    let suggestion: String?
    let isRendererCrash: Bool
    let rawReportPath: String?
}

/// Turns crash reports and log tails into readable diagnoses, and attributes
/// renderer crashes so the automatic fallback chain can react.
/// See the signature table in docs/LAUNCH_FLOW.md.
final class CrashAnalyzer {
    func analyze(instance: Instance, exitCode: Int32) async -> CrashDiagnosis {
        let gameDir = instance.gameDir
        let sources = collectSources(gameDir: gameDir)
        let combined = sources.map(\.content).joined(separator: "\n")
        let reportPath = sources.first?.path

        // Renderer-attributed crashes (drive automatic fallback)
        if combined.contains("libmetalcraft_native")
            || combined.contains("MetalCraft Engine FATAL")
            || (combined.contains("Metal") && combined.contains("MTLDevice")) {
            return CrashDiagnosis(
                headline: "Renderer crash detected",
                detail: "The crash appears to come from the \(instance.renderer.mode.displayName) renderer.",
                suggestion: "The launcher will fall back to a safer renderer automatically. You can also switch modes in the FPS Optimization Center.",
                isRendererCrash: true,
                rawReportPath: reportPath
            )
        }

        if let match = firstMatch(in: combined, pattern: #"java\.lang\.OutOfMemoryError"#) {
            _ = match
            return CrashDiagnosis(
                headline: "Minecraft ran out of memory",
                detail: "The game exceeded its \(instance.memory.maxMB) MB allocation.",
                suggestion: "Raise the RAM slider in instance settings (or the FPS Optimization Center).",
                isRendererCrash: false,
                rawReportPath: reportPath
            )
        }

        if combined.contains("UnsupportedClassVersionError") {
            return CrashDiagnosis(
                headline: "Wrong Java version",
                detail: "This Minecraft version needs a newer Java than the one used.",
                suggestion: "Remove the custom Java path in instance settings and let the launcher pick automatically.",
                isRendererCrash: false,
                rawReportPath: reportPath
            )
        }

        if let mod = firstMatch(in: combined, pattern: #"requires .*? of ([a-z0-9_\-]+)"#) {
            return CrashDiagnosis(
                headline: "Missing mod dependency",
                detail: "A mod requires \"\(mod)\" which isn't installed (or is the wrong version).",
                suggestion: "Open Mods and install the missing dependency from Modrinth.",
                isRendererCrash: false,
                rawReportPath: reportPath
            )
        }

        if combined.contains("GLFW") && combined.contains("main thread") {
            return CrashDiagnosis(
                headline: "macOS threading flag missing",
                detail: "Minecraft on macOS must be started with -XstartOnFirstThread.",
                suggestion: "Use Repair Instance — the launcher will restore the correct launch flags.",
                isRendererCrash: false,
                rawReportPath: reportPath
            )
        }

        return CrashDiagnosis(
            headline: "Minecraft exited unexpectedly (code \(exitCode))",
            detail: sources.isEmpty
                ? "No crash report was produced."
                : "A crash report is available below.",
            suggestion: "Check the Logs tab, or use Repair Instance if files may be corrupted.",
            isRendererCrash: false,
            rawReportPath: reportPath
        )
    }

    // MARK: - Sources

    private struct Source {
        let path: String
        let content: String
    }

    private func collectSources(gameDir: URL) -> [Source] {
        var sources: [Source] = []
        let fm = FileManager.default

        // Newest crash report
        let crashDir = gameDir.appendingPathComponent("crash-reports")
        if let newest = (try? fm.contentsOfDirectory(at: crashDir, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter({ $0.lastPathComponent.hasPrefix("crash-") })
            .max(by: { modified($0) < modified($1) }),
           let content = try? String(contentsOf: newest, encoding: .utf8) {
            sources.append(Source(path: newest.path, content: content))
        }

        // JVM fatal error logs
        if let hsErr = (try? fm.contentsOfDirectory(at: gameDir, includingPropertiesForKeys: nil))?
            .first(where: { $0.lastPathComponent.hasPrefix("hs_err_pid") }),
           let content = try? String(contentsOf: hsErr, encoding: .utf8) {
            sources.append(Source(path: hsErr.path, content: content))
        }

        // Tail of latest.log
        let latest = gameDir.appendingPathComponent("logs/latest.log")
        if let content = try? String(contentsOf: latest, encoding: .utf8) {
            let tail = content.split(separator: "\n").suffix(200).joined(separator: "\n")
            sources.append(Source(path: latest.path, content: tail))
        }

        // Renderer logs
        let rendererDir = gameDir.appendingPathComponent("logs/renderer")
        if let newest = (try? fm.contentsOfDirectory(at: rendererDir, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter({ $0.pathExtension == "log" })
            .max(by: { modified($0) < modified($1) }),
           let content = try? String(contentsOf: newest, encoding: .utf8) {
            sources.append(Source(path: newest.path, content: content))
        }

        return sources
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        let rangeIndex = match.numberOfRanges > 1 ? 1 : 0
        guard let range = Range(match.range(at: rangeIndex), in: text) else { return nil }
        return String(text[range])
    }
}
