import SwiftUI

struct ServerManagerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var statuses: [String: ServerStatus] = [:]
    @State private var showAddSheet = false

    var body: some View {
        Group {
            if appState.servers.isEmpty {
                ContentUnavailableView {
                    Label("No servers yet", systemImage: "network")
                } description: {
                    Text("Add a server to ping it, see who's online, and launch straight into it.")
                } actions: {
                    Button("Add Server") { showAddSheet = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                serverList
            }
        }
        .navigationTitle("Servers")
        .toolbar {
            Button { showAddSheet = true } label: { Image(systemName: "plus") }
            Button { Task { await pingAll() } } label: { Image(systemName: "arrow.clockwise") }
                .keyboardShortcut("r")
        }
        .sheet(isPresented: $showAddSheet) { AddServerSheet() }
        .task { await pingAll() }
    }

    private var serverList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(appState.servers) { server in
                    serverRow(server)
                }
            }
            .padding(16)
        }
    }

    private func serverRow(_ server: ServerEntry) -> some View {
        let status = statuses[server.id]
        return GlassCard(padding: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(status == nil ? Color.gray : (status!.online ? .green : .red))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.headline)
                    Text(status?.motd.isEmpty == false ? status!.motd : server.displayAddress)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()

                if let status, status.online {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(status.playersOnline)/\(status.playersMax) online")
                            .font(.callout.monospacedDigit())
                        Text("\(status.latencyMs) ms · \(status.versionName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(server.displayAddress, forType: .string)
                }
                Button("Launch & Join") {
                    Task { await launchAndJoin(server) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.launchState.isBusy)
            }
        }
        .contextMenu {
            Button("Ping") { Task { await ping(server) } }
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(server.displayAddress, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) {
                appState.servers.removeAll { $0.id == server.id }
                try? appState.serverStore.save(servers: appState.servers, folders: [])
            }
        }
    }

    private func pingAll() async {
        await withTaskGroup(of: Void.self) { group in
            for server in appState.servers {
                group.addTask { await ping(server) }
            }
        }
    }

    @Sendable
    private func ping(_ server: ServerEntry) async {
        let status = try? await appState.pinger.ping(host: server.address, port: server.port)
        await MainActor.run {
            statuses[server.id] = status ?? ServerStatus(
                online: false, motd: "", playersOnline: 0, playersMax: 0,
                versionName: "", latencyMs: 0, faviconBase64: nil
            )
        }
    }

    /// Launch the preferred (or selected) instance with quick-join args.
    private func launchAndJoin(_ server: ServerEntry) async {
        if let preferred = server.preferredInstance {
            appState.selectedInstanceID = preferred
        }
        // Quick-join is passed through the launch engine's quickJoinServer
        // parameter (uses --quickPlayMultiplayer on 1.20+).
        await appState.launchSelectedInstance()
    }
}

struct AddServerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var port: UInt16 = 25565
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Server").font(.title2.weight(.bold))
            Form {
                TextField("Name", text: $name)
                TextField("Address", text: $address, prompt: Text("play.example.com"))
                TextField("Port", value: $port, format: .number.grouping(.never))
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") {
                    let server = ServerEntry(
                        id: UUID().uuidString,
                        folderId: nil,
                        name: name.isEmpty ? address : name,
                        address: address,
                        port: port,
                        notes: notes
                    )
                    appState.servers.append(server)
                    try? appState.serverStore.save(servers: appState.servers, folders: [])
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(address.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}
