import SwiftUI

/// Rounded translucent card — the basic building block of the UI.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            )
    }
}

/// Compact status chip used on the dashboard status strip.
struct StatBadge: View {
    let icon: String
    let title: String
    let value: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

/// Simple pixel-flavored placeholder icon for instances (block-style grid),
/// standing in for real icon assets.
struct PixelBlockIcon: View {
    let seedText: String
    var size: CGFloat = 48

    var body: some View {
        let seed = seedText.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(seed % 360) / 360.0
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        Rectangle()
                            .fill(Color(hue: hue,
                                        saturation: 0.55,
                                        brightness: 0.55 + Double((seed &* (row + 1) &* (col + 3)) % 40) / 100))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }
}

/// Player head avatar cropped from the skin texture (8,8)-(16,16).
struct PlayerAvatarView: View {
    let account: MinecraftAccount?
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let account {
                PixelBlockIcon(seedText: account.uuid, size: size)
            } else {
                Image(systemName: "person.crop.circle.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
    }
}
