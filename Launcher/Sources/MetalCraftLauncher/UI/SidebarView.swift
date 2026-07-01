import SwiftUI

/// Minimal glassy sidebar: translucent material, rounded selection pill,
/// account avatar pinned at the bottom.
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MetalCraft")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .padding(.top, 40)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            ForEach(SidebarSection.allCases.filter { $0 != .settings }) { section in
                sidebarButton(section)
            }

            Spacer()

            sidebarButton(.settings)
            accountFooter
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(_ section: SidebarSection) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                appState.selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(.body, design: .rounded).weight(.medium))
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(appState.selectedSection == section ? Color.accentColor.opacity(0.18) : .clear)
            )
            .foregroundStyle(appState.selectedSection == section ? Color.accentColor : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var accountFooter: some View {
        HStack(spacing: 10) {
            PlayerAvatarView(account: appState.account, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(appState.account?.username ?? "Not signed in")
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if appState.account != nil {
                    Text("Microsoft account")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { appState.presentLogin = true }
    }
}
