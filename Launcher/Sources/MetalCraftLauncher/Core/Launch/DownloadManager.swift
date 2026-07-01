import Foundation

/// Concurrent, checksum-verified downloader. Existing files with matching SHA-1
/// are skipped, so this doubles as the "Repair Instance" verifier.
actor DownloadManager {
    struct Item {
        let url: URL
        let destination: URL
        let sha1: String?
        let size: Int?
    }

    enum DownloadError: LocalizedError {
        case checksumMismatch(URL)
        case http(Int, URL)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch(let url): "Checksum mismatch for \(url.lastPathComponent)"
            case .http(let code, let url): "HTTP \(code) downloading \(url.lastPathComponent)"
            }
        }
    }

    private let session: URLSession
    private let maxConcurrent = 6

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Downloads all items, skipping valid existing files.
    /// `progress` receives (completedCount, totalCount).
    func download(_ items: [Item], progress: @escaping @Sendable (Int, Int) -> Void) async throws {
        let pending = items.filter { !isValid($0) }
        let total = pending.count
        guard total > 0 else {
            progress(0, 0)
            return
        }

        var completed = 0
        var iterator = pending.makeIterator()
        try await withThrowingTaskGroup(of: Void.self) { group in
            var inFlight = 0
            while inFlight < maxConcurrent, let item = iterator.next() {
                group.addTask { try await self.fetch(item) }
                inFlight += 1
            }
            while try await group.next() != nil {
                completed += 1
                progress(completed, total)
                if let item = iterator.next() {
                    group.addTask { try await self.fetch(item) }
                }
            }
        }
    }

    private func isValid(_ item: Item) -> Bool {
        guard FileManager.default.fileExists(atPath: item.destination.path) else { return false }
        guard let sha1 = item.sha1 else { return true }
        return (try? SHA1.hex(ofFileAt: item.destination)) == sha1
    }

    private func fetch(_ item: Item) async throws {
        try FileManager.default.createDirectory(
            at: item.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let (tempURL, response) = try await session.download(from: item.url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw DownloadError.http(status, item.url)
        }
        if let sha1 = item.sha1 {
            guard try SHA1.hex(ofFileAt: tempURL) == sha1 else {
                throw DownloadError.checksumMismatch(item.url)
            }
        }
        try? FileManager.default.removeItem(at: item.destination)
        try FileManager.default.moveItem(at: tempURL, to: item.destination)
    }
}
