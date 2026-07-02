import SwiftUI

// MARK: - Animated aurora background

/// Two soft radial glows in the theme colors drifting slowly behind the
/// content. Cheap to render (20fps timeline, blurred circles) and disabled
/// entirely when "fun effects" is off.
struct AuroraBackground: View {
    let palette: ThemePalette
    var intensity: Double = 0.16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate / 14
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: size.width * 0.7)
                        .position(
                            x: size.width * (0.30 + 0.18 * CGFloat(sin(t))),
                            y: size.height * (0.25 + 0.14 * CGFloat(cos(t * 1.3)))
                        )
                    Circle()
                        .fill(palette.accentSecondary)
                        .frame(width: size.width * 0.6)
                        .position(
                            x: size.width * (0.72 + 0.15 * CGFloat(cos(t * 0.8))),
                            y: size.height * (0.75 + 0.12 * CGFloat(sin(t * 1.1)))
                        )
                }
                .blur(radius: 90)
                .opacity(intensity)
            }
        }
        .allowsHitTesting(false)
        .clipped()
    }
}

// MARK: - Drifting pixel particles

/// Subtle Minecraft-flavored detail: tiny theme-colored squares slowly
/// floating upward, like embers/blocks. Deterministic per index so no state
/// is needed; drawn in a single Canvas pass.
struct PixelParticles: View {
    let palette: ThemePalette
    var count: Int = 22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                for index in 0..<count {
                    let seed = Double(index)
                    let speed = 12.0 + fract(seed * 0.731) * 22.0            // px/s upward
                    let x = fract(seed * 0.377) * size.width
                        + sin(time * 0.5 + seed) * 14
                    let travel = size.height + 40
                    let y = travel - (time * speed + seed * 97).truncatingRemainder(dividingBy: travel)
                    let side = 3.0 + fract(seed * 0.913) * 4.0
                    let opacity = 0.05 + fract(seed * 0.547) * 0.12
                    let color = index.isMultiple(of: 2) ? palette.accent : palette.accentSecondary

                    canvas.fill(
                        Path(roundedRect: CGRect(x: x, y: y - 20, width: side, height: side),
                             cornerRadius: 1),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}

// MARK: - Hover lift

/// Cards scale up slightly and lift their shadow on hover.
struct HoverLift: ViewModifier {
    @State private var hovered = false
    var scale: CGFloat = 1.02

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovered ? scale : 1)
            .shadow(color: .black.opacity(hovered ? 0.22 : 0), radius: hovered ? 14 : 0, y: hovered ? 6 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension View {
    func hoverLift(scale: CGFloat = 1.02) -> some View {
        modifier(HoverLift(scale: scale))
    }
}

// MARK: - Glow pulse

/// Breathing glow, used on the Play button.
struct GlowPulse: ViewModifier {
    let color: Color
    var enabled = true

    func body(content: Content) -> some View {
        if enabled {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let pulse = 0.5 + 0.5 * sin(t * 1.6)
                content
                    .shadow(color: color.opacity(0.35 + 0.25 * pulse),
                            radius: 12 + 8 * pulse, y: 4)
            }
        } else {
            content.shadow(color: color.opacity(0.4), radius: 12, y: 4)
        }
    }
}

extension View {
    func glowPulse(_ color: Color, enabled: Bool = true) -> some View {
        modifier(GlowPulse(color: color, enabled: enabled))
    }
}

// MARK: - Gradient text

extension View {
    /// Fills text (or any view) with the theme gradient.
    func gradientForeground(_ palette: ThemePalette) -> some View {
        foregroundStyle(
            LinearGradient(colors: [palette.accent, palette.accentSecondary],
                           startPoint: .leading, endPoint: .trailing)
        )
    }
}
