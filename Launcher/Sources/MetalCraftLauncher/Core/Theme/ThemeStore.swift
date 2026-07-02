import SwiftUI
import AppKit

/// Built-in color schemes. Each defines an accent pair used for gradients,
/// glows, selection states and the Play button.
enum ThemeScheme: String, CaseIterable, Identifiable {
    case aurora, ember, emerald, midnight, bubblegum, glacier, creeper, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .emerald: "Emerald"
        case .midnight: "Midnight"
        case .bubblegum: "Bubblegum"
        case .glacier: "Glacier"
        case .creeper: "Creeper"
        case .custom: "Custom"
        }
    }
}

struct ThemePalette: Equatable {
    let accent: Color
    let accentSecondary: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Central theme state: selected scheme, custom accent, appearance mode and
/// the "fun effects" switch. Persists to UserDefaults; injected app-wide as
/// an EnvironmentObject so every view re-renders on change.
@MainActor
final class ThemeStore: ObservableObject {
    @Published var scheme: ThemeScheme {
        didSet { defaults.set(scheme.rawValue, forKey: "themeScheme") }
    }
    @Published var customAccentHex: String {
        didSet { defaults.set(customAccentHex, forKey: "themeCustomAccent") }
    }
    @Published var funEffects: Bool {
        didSet { defaults.set(funEffects, forKey: "themeFunEffects") }
    }
    /// "system" | "dark" | "light"
    @Published var appearance: String {
        didSet { defaults.set(appearance, forKey: "theme") }
    }

    private let defaults = UserDefaults.standard

    init() {
        scheme = ThemeScheme(rawValue: defaults.string(forKey: "themeScheme") ?? "") ?? .aurora
        customAccentHex = defaults.string(forKey: "themeCustomAccent") ?? "#4C8DFF"
        funEffects = defaults.object(forKey: "themeFunEffects") as? Bool ?? true
        appearance = defaults.string(forKey: "theme") ?? "system"
    }

    var palette: ThemePalette {
        Self.palette(for: scheme, customHex: customAccentHex)
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    static func palette(for scheme: ThemeScheme, customHex: String = "#4C8DFF") -> ThemePalette {
        switch scheme {
        case .aurora:
            ThemePalette(accent: Color(hex: "#4C8DFF"), accentSecondary: Color(hex: "#9B5CFF"))
        case .ember:
            ThemePalette(accent: Color(hex: "#FF7A3D"), accentSecondary: Color(hex: "#FF3D5A"))
        case .emerald:
            ThemePalette(accent: Color(hex: "#2FD27D"), accentSecondary: Color(hex: "#1FB6A6"))
        case .midnight:
            ThemePalette(accent: Color(hex: "#5C6CFF"), accentSecondary: Color(hex: "#2B3BCC"))
        case .bubblegum:
            ThemePalette(accent: Color(hex: "#FF5CA8"), accentSecondary: Color(hex: "#B15CFF"))
        case .glacier:
            ThemePalette(accent: Color(hex: "#38C7E3"), accentSecondary: Color(hex: "#3D7BFF"))
        case .creeper:
            ThemePalette(accent: Color(hex: "#3DBB3D"), accentSecondary: Color(hex: "#1E7A2E"))
        case .custom:
            ThemePalette(accent: Color(hex: customHex),
                         accentSecondary: Color(hex: customHex).shifted(by: 0.55))
        }
    }
}

// MARK: - Color helpers

extension Color {
    /// "#RRGGBB" (with or without the #). Falls back to blue on bad input.
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        var rgb: UInt64 = 0
        guard value.count == 6, Scanner(string: value).scanHexInt64(&rgb) else {
            self = .blue
            return
        }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// Hex string for persistence (sRGB).
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X",
                      Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)),
                      Int(round(ns.blueComponent * 255)))
    }

    /// A hue-rotated companion color, used to build a gradient from one
    /// user-picked custom accent.
    func shifted(by amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        ns.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let newHue = (hue + amount * 0.12).truncatingRemainder(dividingBy: 1)
        return Color(hue: Double(newHue),
                     saturation: Double(min(1, saturation + 0.1)),
                     brightness: Double(max(0.35, brightness - 0.1)))
    }
}
