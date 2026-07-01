import Foundation

/// Detects installed Java runtimes, picks the right major version per Minecraft
/// version, and downloads architecture-native Temurin builds when needed
/// (aarch64 on Apple Silicon — no Rosetta penalty; x64 on Intel).
final class JavaRuntimeManager {
    struct Runtime: Codable, Identifiable, Equatable {
        var id: String { home }
        let home: String          // JAVA_HOME
        let executable: String    // .../bin/java
        let majorVersion: Int
        let architecture: String  // "aarch64" | "x86_64"
        let vendor: String
        let isManaged: Bool       // downloaded by this launcher
    }

    enum JavaError: LocalizedError {
        case noneAvailable(Int)
        var errorDescription: String? {
            if case .noneAvailable(let major) = self {
                return "No Java \(major) runtime available and download failed."
            }
            return nil
        }
    }

    /// Java major version required per Minecraft version (from the version JSON
    /// when present; this table is the offline fallback).
    static func requiredMajor(forMinecraft version: String) -> Int {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2, parts[0] == 1 else { return 21 }
        let minor = parts[1]
        let patch = parts.count > 2 ? parts[2] : 0
        switch minor {
        case ..<17: return 8
        case 17: return 16
        case 18...20 where minor == 20 && patch >= 5: return 21
        case 18...20: return 17
        default: return 21
        }
    }

    /// Scan the standard macOS locations plus our managed runtimes folder.
    func detectInstalled() -> [Runtime] {
        var found: [Runtime] = []
        let fm = FileManager.default

        var searchRoots = [
            URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Java/JavaVirtualMachines"),
            Paths.javaRuntimes
        ]
        // Common package-manager locations
        searchRoots.append(URL(fileURLWithPath: "/opt/homebrew/opt"))
        searchRoots.append(URL(fileURLWithPath: "/usr/local/opt"))

        for root in searchRoots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                for candidate in [
                    child.appendingPathComponent("Contents/Home"),
                    child   // managed runtimes are extracted with Home at top level
                ] {
                    let java = candidate.appendingPathComponent("bin/java")
                    guard fm.isExecutableFile(atPath: java.path) else { continue }
                    if let runtime = probe(executable: java, home: candidate, managed: root == Paths.javaRuntimes) {
                        found.append(runtime)
                    }
                    break
                }
            }
        }
        return found
    }

    /// Best runtime for an instance: explicit path > major override > version JSON
    /// requirement, preferring native-architecture managed builds.
    func resolveRuntime(for instance: Instance, versionJSON: VersionJSON?) async throws -> Runtime {
        if let custom = instance.java.path {
            let url = URL(fileURLWithPath: custom)
            if let runtime = probe(executable: url, home: url.deletingLastPathComponent().deletingLastPathComponent(), managed: false) {
                return runtime
            }
        }

        let major = instance.java.majorOverride
            ?? versionJSON?.javaVersion?.majorVersion
            ?? Self.requiredMajor(forMinecraft: instance.minecraftVersion)

        let nativeArch = HardwareReport.current().isAppleSilicon ? "aarch64" : "x86_64"
        let installed = detectInstalled()
        if let best = installed
            .filter({ $0.majorVersion == major })
            .sorted(by: { ($0.architecture == nativeArch ? 0 : 1) < ($1.architecture == nativeArch ? 0 : 1) })
            .first {
            return best
        }

        return try await downloadTemurin(major: major, nativeArch: nativeArch)
    }

    /// Download an Eclipse Temurin JRE from the official Adoptium API.
    func downloadTemurin(major: Int, nativeArch: String) async throws -> Runtime {
        let apiArch = nativeArch == "x86_64" ? "x64" : "aarch64"
        let api = "https://api.adoptium.net/v3/binary/latest/\(major)/ga/mac/\(apiArch)/jre/hotspot/normal/eclipse"
        guard let url = URL(string: api) else { throw JavaError.noneAvailable(major) }

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 0) else {
            throw JavaError.noneAvailable(major)
        }

        let dest = Paths.javaRuntimes.appendingPathComponent("temurin-\(major)-\(apiArch)", isDirectory: true)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // Adoptium mac binaries are .tar.gz
        let untar = Process()
        untar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        untar.arguments = ["xzf", tempURL.path, "-C", dest.path, "--strip-components=1"]
        try untar.run()
        untar.waitUntilExit()
        guard untar.terminationStatus == 0 else { throw JavaError.noneAvailable(major) }

        let home = dest.appendingPathComponent("Contents/Home")
        let java = home.appendingPathComponent("bin/java")
        guard let runtime = probe(executable: java, home: home, managed: true) else {
            throw JavaError.noneAvailable(major)
        }
        return runtime
    }

    // MARK: - Probing

    /// Runs `java -version` and parses version + arch from the output.
    private func probe(executable: URL, home: URL, managed: Bool) -> Runtime? {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-XshowSettings:properties", "-version"]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()

        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return nil }

        func property(_ name: String) -> String? {
            output.split(separator: "\n")
                .first { $0.contains("\(name) = ") }?
                .split(separator: "=", maxSplits: 1).last
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        guard let versionString = property("java.version") else { return nil }
        let major: Int
        if versionString.hasPrefix("1.") {
            major = Int(versionString.split(separator: ".")[1]) ?? 8
        } else {
            major = Int(versionString.split(separator: ".").first ?? "") ?? 0
        }
        guard major > 0 else { return nil }

        return Runtime(
            home: home.path,
            executable: executable.path,
            majorVersion: major,
            architecture: property("os.arch") ?? "unknown",
            vendor: property("java.vendor") ?? "Unknown",
            isManaged: managed
        )
    }
}
