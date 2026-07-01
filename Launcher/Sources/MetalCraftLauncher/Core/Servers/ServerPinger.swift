import Foundation
import Network

/// Modern Minecraft Server List Ping (SLP) over Network.framework.
/// Protocol: handshake (state=1) + status request → JSON status response.
final class ServerPinger {
    enum PingError: Error {
        case connectionFailed, malformedResponse, timeout
    }

    func ping(host: String, port: UInt16, timeout: TimeInterval = 5) async throws -> ServerStatus {
        let start = Date()
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 25565,
            using: .tcp
        )

        return try await withThrowingTaskGroup(of: ServerStatus.self) { group in
            group.addTask {
                try await self.performPing(connection: connection, host: host, port: port, start: start)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                connection.cancel()
                throw PingError.timeout
            }
            defer { group.cancelAll(); connection.cancel() }
            guard let result = try await group.next() else { throw PingError.timeout }
            return result
        }
    }

    private func performPing(connection: NWConnection, host: String, port: UInt16, start: Date) async throws -> ServerStatus {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed, .cancelled: cont.resume(throwing: PingError.connectionFailed)
                default: break
                }
            }
            connection.start(queue: .global())
        }
        connection.stateUpdateHandler = nil

        // Handshake packet: id 0x00, protocol version -1, host, port, next state 1
        var handshake = Data()
        handshake.append(varInt(0x00))
        handshake.append(varInt(-1))
        handshake.append(varInt(Int32(host.utf8.count)))
        handshake.append(Data(host.utf8))
        handshake.append(contentsOf: [UInt8(port >> 8), UInt8(port & 0xFF)])
        handshake.append(varInt(1))

        try await send(connection, framed(handshake))
        try await send(connection, framed(Data([0x00])))   // status request

        // Response: [length varint][packet id varint][json length varint][json]
        var buffer = Data()
        let totalLength = try await readVarInt(connection, &buffer)
        while buffer.count < totalLength {
            buffer.append(try await receive(connection, max: 65536))
        }
        var offset = 0
        _ = try readVarInt(from: buffer, offset: &offset)          // packet id
        let jsonLength = try readVarInt(from: buffer, offset: &offset)
        let jsonData = buffer.subdata(in: offset..<min(offset + Int(jsonLength), buffer.count))

        let latency = Int(Date().timeIntervalSince(start) * 1000)
        return try parse(jsonData: jsonData, latencyMs: latency)
    }

    // MARK: - Status JSON

    private func parse(jsonData: Data, latencyMs: Int) throws -> ServerStatus {
        guard let object = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw PingError.malformedResponse
        }
        let players = object["players"] as? [String: Any]
        let version = object["version"] as? [String: Any]

        // MOTD ("description") is either a plain string or a chat component tree.
        let motd: String
        if let text = object["description"] as? String {
            motd = text
        } else if let component = object["description"] as? [String: Any] {
            motd = Self.flattenChatComponent(component)
        } else {
            motd = ""
        }

        return ServerStatus(
            online: true,
            motd: motd,
            playersOnline: players?["online"] as? Int ?? 0,
            playersMax: players?["max"] as? Int ?? 0,
            versionName: version?["name"] as? String ?? "unknown",
            latencyMs: latencyMs,
            faviconBase64: (object["favicon"] as? String)?
                .replacingOccurrences(of: "data:image/png;base64,", with: "")
        )
    }

    private static func flattenChatComponent(_ component: [String: Any]) -> String {
        var text = component["text"] as? String ?? ""
        if let extras = component["extra"] as? [[String: Any]] {
            text += extras.map(flattenChatComponent).joined()
        }
        // Strip legacy § color codes for a clean plain-text MOTD
        var result = ""
        var skip = false
        for character in text {
            if skip { skip = false; continue }
            if character == "§" { skip = true; continue }
            result.append(character)
        }
        return result
    }

    // MARK: - Wire helpers

    private func framed(_ packet: Data) -> Data {
        varInt(Int32(packet.count)) + packet
    }

    private func varInt(_ value: Int32) -> Data {
        var v = UInt32(bitPattern: value)
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    private func readVarInt(from data: Data, offset: inout Int) throws -> Int32 {
        var result: UInt32 = 0
        var shift: UInt32 = 0
        while true {
            guard offset < data.count else { throw PingError.malformedResponse }
            let byte = data[data.startIndex + offset]
            offset += 1
            result |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            guard shift < 35 else { throw PingError.malformedResponse }
        }
        return Int32(bitPattern: result)
    }

    private func readVarInt(_ connection: NWConnection, _ spillover: inout Data) async throws -> Int32 {
        var result: UInt32 = 0
        var shift: UInt32 = 0
        while true {
            let byte: UInt8
            if !spillover.isEmpty {
                byte = spillover.removeFirst()
            } else {
                let chunk = try await receive(connection, max: 65536)
                guard !chunk.isEmpty else { throw PingError.malformedResponse }
                spillover = chunk
                byte = spillover.removeFirst()
            }
            result |= UInt32(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            guard shift < 35 else { throw PingError.malformedResponse }
        }
        return Int32(bitPattern: result)
    }

    private func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func receive(_ connection: NWConnection, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: data ?? Data()) }
            }
        }
    }
}
