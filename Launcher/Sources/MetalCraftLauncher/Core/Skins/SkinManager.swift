import Foundation
import AppKit

/// Skin management via the official Minecraft services API plus a local library.
final class SkinManager {
    private let session: URLSession
    private let libraryFile = Paths.skins.appendingPathComponent("library.json")

    init(session: URLSession = .shared) {
        self.session = session
    }

    enum SkinError: LocalizedError {
        case invalidDimensions
        case notPNG
        case uploadFailed(Int)

        var errorDescription: String? {
            switch self {
            case .invalidDimensions: "Skins must be 64×64 (or legacy 64×32) pixels."
            case .notPNG: "Skins must be PNG files."
            case .uploadFailed(let code): "Skin upload failed (HTTP \(code))."
            }
        }
    }

    struct LibrarySkin: Codable, Identifiable {
        let id: String
        var name: String
        var file: String
        var model: MinecraftAccount.SkinModel
        var added: Date
    }

    // MARK: - Validation

    /// Valid skin: PNG, 64×64 (modern) or 64×32 (legacy).
    func validate(skinAt url: URL) throws {
        guard url.pathExtension.lowercased() == "png",
              let image = NSImage(contentsOf: url),
              let rep = image.representations.first as? NSBitmapImageRep else {
            throw SkinError.notPNG
        }
        let (w, h) = (rep.pixelsWide, rep.pixelsHigh)
        guard w == 64 && (h == 64 || h == 32) else { throw SkinError.invalidDimensions }
    }

    // MARK: - Official API

    /// Upload and activate a skin on the signed-in account (official endpoint).
    func upload(skinAt url: URL, model: MinecraftAccount.SkinModel, accessToken: String) async throws {
        try validate(skinAt: url)
        let skinData = try Data(contentsOf: url)

        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/minecraft/profile/skins")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let boundary = "metalcraft-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("variant", model == .slim ? "slim" : "classic")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"skin.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(skinData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw SkinError.uploadFailed(status) }
    }

    /// Fetch the current skin texture for preview rendering.
    func fetchSkinTexture(for account: MinecraftAccount) async throws -> Data? {
        guard let url = account.skinURL else { return nil }
        let (data, _) = try await session.data(from: url)
        return data
    }

    // MARK: - Local library

    func library() -> [LibrarySkin] {
        guard let data = try? Data(contentsOf: libraryFile) else { return [] }
        struct Wrapper: Codable { let skins: [LibrarySkin] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Wrapper.self, from: data).skins) ?? []
    }

    func addToLibrary(skinAt url: URL, name: String, model: MinecraftAccount.SkinModel) throws -> LibrarySkin {
        try validate(skinAt: url)
        let id = UUID().uuidString
        let filename = "\(id).png"
        try FileManager.default.copyItem(at: url, to: Paths.skins.appendingPathComponent(filename))

        var skins = library()
        let skin = LibrarySkin(id: id, name: name, file: filename, model: model, added: Date())
        skins.append(skin)
        try persist(skins)
        return skin
    }

    func removeFromLibrary(_ skin: LibrarySkin) throws {
        try? FileManager.default.removeItem(at: Paths.skins.appendingPathComponent(skin.file))
        try persist(library().filter { $0.id != skin.id })
    }

    private func persist(_ skins: [LibrarySkin]) throws {
        struct Wrapper: Codable {
            var schemaVersion = 1
            let skins: [LibrarySkin]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Wrapper(skins: skins)).write(to: libraryFile, options: .atomic)
    }
}
