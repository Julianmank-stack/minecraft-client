import Foundation

/// Official Microsoft → Xbox Live → XSTS → Minecraft Services authentication.
/// Device-code OAuth flow: the user signs in on microsoft.com in their browser;
/// this app never sees a password and stores only OAuth tokens (in the Keychain).
///
/// Cracked/offline accounts are intentionally unsupported.
final class MicrosoftAuthService {
    /// Azure AD application (public client, "Allow public client flows" enabled,
    /// approved for the Minecraft API). Set your own client id here.
    static let clientID = ProcessInfo.processInfo.environment["METALCRAFT_MSA_CLIENT_ID"]
        ?? "00000000-0000-0000-0000-000000000000"

    private let keychain: KeychainStore
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(keychain: KeychainStore, session: URLSession = .shared) {
        self.keychain = keychain
        self.session = session
    }

    enum AuthError: LocalizedError {
        case declined
        case timedOut
        case noXboxProfile
        case childAccount
        case doesNotOwnMinecraft
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .declined: "Sign-in was cancelled."
            case .timedOut: "Sign-in timed out — please try again."
            case .noXboxProfile: "This Microsoft account has no Xbox profile. Create one at xbox.com and try again."
            case .childAccount: "Child accounts must be added to a family by an adult before playing."
            case .doesNotOwnMinecraft: "This account doesn't own Minecraft: Java Edition."
            case .http(let code): "Authentication service error (HTTP \(code))."
            }
        }
    }

    struct DeviceCode: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let interval: Int
        let expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationUri = "verification_uri"
            case interval, expiresIn = "expires_in"
        }
    }

    // MARK: - Public API

    /// Step 1: begin the device-code flow. The UI shows `userCode` and opens
    /// `verificationUri` in the default browser.
    func requestDeviceCode() async throws -> DeviceCode {
        try await postForm(
            url: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode",
            body: [
                "client_id": Self.clientID,
                "scope": "XboxLive.signin offline_access"
            ]
        )
    }

    /// Step 2: poll for the user completing browser sign-in, then run the full
    /// Xbox → XSTS → Minecraft chain and return the signed-in account.
    func completeSignIn(deviceCode: DeviceCode) async throws -> MinecraftAccount {
        let msa = try await pollForMSAToken(deviceCode: deviceCode)
        let account = try await signInWithMSA(accessToken: msa.accessToken)
        try keychain.saveString(msa.refreshToken, forKey: "\(account.id.uuidString).msa")
        return account
    }

    /// Restore the previous session silently using the stored refresh token.
    func restoreSession() async throws -> MinecraftAccount? {
        guard let stored = try loadStoredAccount() else { return nil }

        if let token = keychain.loadCodable(MinecraftToken.self, forKey: "\(stored.id.uuidString).mc"),
           !token.isExpiringSoon {
            return stored
        }
        guard let refresh = keychain.loadString(forKey: "\(stored.id.uuidString).msa") else { return nil }

        let msa: MSAToken = try await postForm(
            url: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
            body: [
                "client_id": Self.clientID,
                "grant_type": "refresh_token",
                "refresh_token": refresh,
                "scope": "XboxLive.signin offline_access"
            ]
        )
        try keychain.saveString(msa.refreshToken, forKey: "\(stored.id.uuidString).msa")
        return try await signInWithMSA(accessToken: msa.accessToken, reuseID: stored.id)
    }

    /// A valid Minecraft access token for launching, refreshing if needed.
    func minecraftToken(for account: MinecraftAccount) async throws -> String {
        if let token = keychain.loadCodable(MinecraftToken.self, forKey: "\(account.id.uuidString).mc"),
           !token.isExpiringSoon {
            return token.accessToken
        }
        guard let restored = try await restoreSession(), restored.id == account.id,
              let token = keychain.loadCodable(MinecraftToken.self, forKey: "\(account.id.uuidString).mc") else {
            throw AuthError.declined
        }
        return token.accessToken
    }

    func signOut(_ account: MinecraftAccount) {
        keychain.delete(forKey: "\(account.id.uuidString).msa")
        keychain.delete(forKey: "\(account.id.uuidString).mc")
        try? FileManager.default.removeItem(at: Paths.accountsFile)
    }

    // MARK: - Chain internals

    private struct MSAToken: Decodable {
        let accessToken: String
        let refreshToken: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private func pollForMSAToken(deviceCode: DeviceCode) async throws -> MSAToken {
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        while Date() < deadline {
            try await Task.sleep(for: .seconds(deviceCode.interval))
            do {
                return try await postForm(
                    url: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token",
                    body: [
                        "client_id": Self.clientID,
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                        "device_code": deviceCode.deviceCode
                    ]
                )
            } catch PendingAuth.pending {
                continue // user hasn't finished in the browser yet
            }
        }
        throw AuthError.timedOut
    }

    private enum PendingAuth: Error { case pending }

    private func signInWithMSA(accessToken: String, reuseID: UUID? = nil) async throws -> MinecraftAccount {
        // Xbox Live user token
        let xbl: XboxResponse = try await postJSON(
            url: "https://user.auth.xboxlive.com/user/authenticate",
            body: [
                "Properties": [
                    "AuthMethod": "RPS",
                    "SiteName": "user.auth.xboxlive.com",
                    "RpsTicket": "d=\(accessToken)"
                ],
                "RelyingParty": "http://auth.xboxlive.com",
                "TokenType": "JWT"
            ]
        )

        // XSTS token
        let xsts: XboxResponse
        do {
            xsts = try await postJSON(
                url: "https://xsts.auth.xboxlive.com/xsts/authorize",
                body: [
                    "Properties": ["SandboxId": "RETAIL", "UserTokens": [xbl.token]],
                    "RelyingParty": "rp://api.minecraftservices.com/",
                    "TokenType": "JWT"
                ]
            )
        } catch XboxError.xerr(let code) {
            switch code {
            case 2148916233: throw AuthError.noXboxProfile
            case 2148916238: throw AuthError.childAccount
            default: throw AuthError.http(Int(code))
            }
        }

        // Minecraft Services token
        let mc: MCTokenResponse = try await postJSON(
            url: "https://api.minecraftservices.com/authentication/login_with_xbox",
            body: ["identityToken": "XBL3.0 x=\(xbl.userHash);\(xsts.token)"]
        )

        // Profile
        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/minecraft/profile")!)
        request.setValue("Bearer \(mc.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { throw AuthError.doesNotOwnMinecraft }
        let profile = try decoder.decode(MCProfile.self, from: data)

        let account = MinecraftAccount(
            id: reuseID ?? UUID(),
            username: profile.name,
            uuid: profile.id,
            skinURL: profile.skins.first(where: { $0.state == "ACTIVE" }).flatMap { URL(string: $0.url) },
            skinModel: profile.skins.first(where: { $0.state == "ACTIVE" })?.variant == "SLIM" ? .slim : .classic,
            capeURL: profile.capes.first(where: { $0.state == "ACTIVE" }).flatMap { URL(string: $0.url) },
            lastRefresh: Date()
        )

        try keychain.saveCodable(
            MinecraftToken(accessToken: mc.accessToken, expiresAt: Date().addingTimeInterval(TimeInterval(mc.expiresIn))),
            forKey: "\(account.id.uuidString).mc"
        )
        try persistAccount(account)
        return account
    }

    // MARK: - Wire models

    private struct XboxResponse: Decodable {
        let token: String
        let userHash: String

        enum CodingKeys: String, CodingKey { case Token, DisplayClaims }
        enum ClaimKeys: String, CodingKey { case xui }
        struct XUI: Decodable { let uhs: String }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            token = try container.decode(String.self, forKey: .Token)
            let claims = try container.nestedContainer(keyedBy: ClaimKeys.self, forKey: .DisplayClaims)
            userHash = try claims.decode([XUI].self, forKey: .xui).first?.uhs ?? ""
        }
    }

    private enum XboxError: Error { case xerr(Int64) }

    private struct MCTokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
        }
    }

    private struct MCProfile: Decodable {
        struct Skin: Decodable { let url: String; let state: String; let variant: String? }
        struct Cape: Decodable { let url: String; let state: String }
        let id: String
        let name: String
        let skins: [Skin]
        let capes: [Cape]
    }

    // MARK: - HTTP helpers

    private func postForm<T: Decodable>(url: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400,
           let err = try? decoder.decode([String: String].self, from: data),
           err["error"] == "authorization_pending" {
            throw PendingAuth.pending
        }
        guard (200..<300).contains(status) else { throw AuthError.http(status) }
        return try decoder.decode(T.self, from: data)
    }

    private func postJSON<T: Decodable>(url: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401,
           let err = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let xerr = err["XErr"] as? Int64 {
            throw XboxError.xerr(xerr)
        }
        guard (200..<300).contains(status) else { throw AuthError.http(status) }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Local metadata persistence (no secrets)

    private func persistAccount(_ account: MinecraftAccount) throws {
        let wrapper = ["schemaVersion": AnyEncodable(1), "accounts": AnyEncodable([account])]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(wrapper).write(to: Paths.accountsFile, options: .atomic)
    }

    private func loadStoredAccount() throws -> MinecraftAccount? {
        guard let data = try? Data(contentsOf: Paths.accountsFile) else { return nil }
        struct Wrapper: Decodable { let accounts: [MinecraftAccount] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Wrapper.self, from: data).accounts.first
    }
}

/// Minimal type-erased Encodable for mixed-value JSON wrappers.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) { encodeFunc = { try value.encode(to: $0) } }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
