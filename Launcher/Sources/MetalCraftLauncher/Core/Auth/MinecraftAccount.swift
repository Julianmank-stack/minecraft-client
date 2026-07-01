import Foundation

struct MinecraftAccount: Codable, Identifiable, Equatable {
    let id: UUID              // launcher-local id
    var username: String
    var uuid: String          // Minecraft profile UUID
    var skinURL: URL?
    var skinModel: SkinModel
    var capeURL: URL?
    var lastRefresh: Date

    enum SkinModel: String, Codable {
        case classic, slim
    }

    var avatarURL: URL? {
        // Face render from the official UUID via a well-known avatar service is
        // avoided; we crop the face client-side from skinURL instead.
        skinURL
    }
}

/// Short-lived Minecraft access token, kept in the Keychain (never on disk).
struct MinecraftToken: Codable {
    let accessToken: String
    let expiresAt: Date

    var isExpiringSoon: Bool { expiresAt.timeIntervalSinceNow < 300 }
}
