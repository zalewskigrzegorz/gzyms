import Foundation

/// Every colour Gzyms draws, by name. Views read colours only from here, never a hex of their own.
public struct Theme: Equatable, Sendable {
    public var name: String
    public var base, surface, overlay, text: String
    public var mauve, pink, lavender, green, gold, peach, red, sky: String
    /// The HUD's own background, darker than the bar so it reads as a separate window.
    public var hud: String
    /// The banner island: pure black, so on a notch screen it reads as the notch growing down.
    public var island = "#000000"

    /// ~/Code/dotfiles/docs/mocha-neon-palette.md. `surface` is the prototype's chip background.
    public static let mochaNeon = Theme(
        name: "mocha-neon", base: "#1E1E2E", surface: "#2A2A3D", overlay: "#7F849C", text: "#F0F0FF",
        mauve: "#B347FF", pink: "#FF80BF", lavender: "#9580FF", green: "#50FA7B", gold: "#FFD700",
        peach: "#FF8C42", red: "#FF6B9D", sky: "#8BE9FD", hud: "#0A0A12")

    /// Accents differ only in lightness; `red` is white so "hot" still stands out.
    public static let grayscale = Theme(
        name: "grayscale", base: "#1C1C1C", surface: "#2E2E2E", overlay: "#808080", text: "#F0F0F0",
        mauve: "#BDBDBD", pink: "#D0D0D0", lavender: "#A8A8A8", green: "#9E9E9E", gold: "#E0E0E0",
        peach: "#C4C4C4", red: "#FFFFFF", sky: "#B0B0B0", hud: "#0E0E0E")

    /// Gzyms' own two, first in every list.
    public static let builtIn = [mochaNeon, grayscale]
    /// The built-in ones, then the terminal palettes tuios ships that read well, plus the popular ones made to
    /// (Themes.gen.swift, scripts/gen-themes.py), A to Z.
    public static let all = builtIn + terminalPalettes.split(separator: "\n").compactMap { terminal(String($0)) }

    public static func named(_ name: String) -> Theme? { all.first { $0.name == name } }

    /// A dark background: system controls (buttons, sliders, popover edges) are drawn dark to match, else light.
    public var isDark: Bool { Self.luminance(String(base.dropFirst())) < 0.5 }

    /// One line of Themes.gen.swift: the id, then every token in the order of `Theme`'s fields, as hex.
    /// The colours are worked out in scripts/gen-themes.py, where the contrast rules live.
    static func terminal(_ line: String) -> Theme? {
        let p = line.split(separator: " ").map(String.init)
        guard p.count == 14, p.dropFirst().allSatisfy({ $0.wholeMatch(of: /[0-9a-fA-F]{6}/) != nil }) else { return nil }
        let h = p.dropFirst().map(hex)
        return Theme(name: p[0], base: h[0], surface: h[1], overlay: h[2], text: h[3], mauve: h[4], pink: h[5], lavender: h[6],
                     green: h[7], gold: h[8], peach: h[9], red: h[10], sky: h[11], hud: h[12])
    }

    /// WCAG contrast of two "#RRGGBB" colours, 1 to 21.
    public static func contrast(_ a: String, _ b: String) -> Double {
        func lum(_ s: String) -> Double {
            rgb(String(s.dropFirst())).map { c in let v = c / 255; return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
                .enumerated().map { [0.2126, 0.7152, 0.0722][$0.offset] * $0.element }.reduce(0, +)
        }
        let (x, y) = (lum(a), lum(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func hex(_ s: String) -> String { "#" + s.uppercased() }

    private static func rgb(_ s: String) -> [Double] {
        let v = Int(s, radix: 16) ?? 0
        return [Double(v >> 16 & 255), Double(v >> 8 & 255), Double(v & 255)]
    }

    private static func luminance(_ s: String) -> Double {
        let c = rgb(s)
        return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255
    }

    /// A token name ("green") or a "#RRGGBB" hex; nil for anything else.
    public func resolve(_ color: String) -> String? {
        if color.wholeMatch(of: /#[0-9A-Fa-f]{6}/) != nil { return color.uppercased() }
        return switch color {
        case "base": base
        case "surface": surface
        case "overlay": overlay
        case "text": text
        case "mauve": mauve
        case "pink": pink
        case "lavender": lavender
        case "green": green
        case "gold": gold
        case "peach": peach
        case "red": red
        case "sky": sky
        default: nil
        }
    }
}

public enum CPUChart: String, Sendable { case line, bars }

/// `config.toml` with its top-level `theme` set to `name`; the rest of the file is left as it is.
public func settingTheme(_ name: String, in toml: String?) -> String {
    setting("theme", to: .string(name), in: .table([]), toml: toml)
}
