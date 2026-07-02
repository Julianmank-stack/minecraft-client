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

/// Live macOS thermal-pressure chip (nominal → critical), with the real CPU
/// die temperature next to it when the sensor interface is available.
struct ThermalBadge: View {
    let state: ProcessInfo.ThermalState
    var reading: ThermalSensorReader.Reading?

    private var info: (label: String, icon: String, tint: Color) {
        switch state {
        case .nominal: ("Cool", "thermometer.low", .green)
        case .fair: ("Warm", "thermometer.medium", .yellow)
        case .serious: ("Hot", "thermometer.high", .orange)
        case .critical: ("Critical", "flame.fill", .red)
        @unknown default: ("Unknown", "thermometer.medium", .gray)
        }
    }

    private var label: String {
        if let temp = reading?.cpuC ?? reading?.hottestC {
            "\(info.label) · \(Int(temp.rounded()))°"
        } else {
            info.label
        }
    }

    var body: some View {
        Label(label, systemImage: info.icon)
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(info.tint.opacity(0.16)))
            .foregroundStyle(info.tint)
            .help(helpText)
    }

    private var helpText: String {
        var text = "macOS thermal pressure — Thermal Guard reacts to Hot and Critical"
        if let reading {
            var parts: [String] = []
            if let cpu = reading.cpuC { parts.append("CPU \(Int(cpu.rounded()))°C") }
            if let gpu = reading.gpuC { parts.append("GPU \(Int(gpu.rounded()))°C") }
            if parts.isEmpty { parts.append("Hottest sensor \(Int(reading.hottestC.rounded()))°C") }
            text += "\n" + parts.joined(separator: " · ")
        }
        return text
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
