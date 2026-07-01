import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: LogFilter = .all
    @State private var searchText = ""

    enum LogFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case launcher = "Launcher"
        case game = "Game"
        case renderer = "Renderer"
        var id: String { rawValue }
    }

    private var visibleLines: [LogLine] {
        appState.liveLogLines.filter { line in
            let matchesFilter = switch filter {
            case .all: true
            case .launcher: line.source == .launcher
            case .game: line.source == .game
            case .renderer: line.source == .renderer
            }
            let matchesSearch = searchText.isEmpty || line.text.localizedCaseInsensitiveContains(searchText)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(LogFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            if let diagnosis = appState.lastCrashDiagnosis {
                GlassCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(diagnosis.headline, systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(diagnosis.detail).font(.callout)
                        if let suggestion = diagnosis.suggestion {
                            Text(suggestion).font(.callout).foregroundStyle(.secondary)
                        }
                        if let path = diagnosis.rawReportPath {
                            Button("Reveal crash report in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleLines) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Text(line.date, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.tertiary)
                                Text(line.text)
                                    .foregroundStyle(color(for: line))
                                    .textSelection(.enabled)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .id(line.id)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: appState.liveLogLines.count) {
                    if let last = visibleLines.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search logs")
        .navigationTitle("Logs")
        .toolbar {
            if let instance = appState.selectedInstance {
                Button("Open Logs Folder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [instance.gameDir.appendingPathComponent("logs")]
                    )
                }
            }
        }
    }

    private func color(for line: LogLine) -> Color {
        if line.text.contains("ERROR") || line.text.contains("FATAL") { return .red }
        if line.text.contains("WARN") { return .orange }
        if line.source == .launcher { return .secondary }
        return .primary
    }
}
