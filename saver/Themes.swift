import Foundation

/// Colour themes after Omarchy's built-in themes. A theme recolours the effects
/// (the gradient the logo settles into, plus each effect's signature colours),
/// the background, and the pixel clock. "omarchy" keeps ttfx's own colours.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let background: UInt32          // 0xRRGGBB
    let foreground: UInt32          // clock and date
    let stops: [String]             // final gradient, darkest → brightest; empty = ttfx defaults
    let accents: [String]           // effect colours (beams, rain, fireworks, …)

    /// The ttfx command for `command` ("name [options]") in this theme.
    func command(for command: String) -> String {
        guard !stops.isEmpty else { return command }
        var parts = command.split(separator: " ").map(String.init)
        guard let name = parts.first else { return command }
        parts.append(contentsOf: name == "synthgrid" ? ["--text-gradient-stops"] + stops : ["--final-gradient-stops"] + stops)
        let a = accents.joined(separator: " ")
        switch name {
        case "beams": parts += ["--beam-gradient-stops", a]
        case "matrix": parts += ["--rain-color-gradient", a]
        case "thunderstorm": parts += ["--lightning-color", accents.last!, "--glowing-text-color", accents.first!]
        case "rain": parts += ["--rain-colors", a]
        case "fireworks": parts += ["--firework-colors", a]
        case "bubbles": parts += ["--bubble-colors", a]
        case "rings": parts += ["--ring-colors", a]
        case "waves": parts += ["--wave-gradient-stops", a]
        case "bouncyballs": parts += ["--ball-colors", a]
        case "blackhole": parts += ["--star-colors", a]
        case "synthgrid": parts += ["--grid-gradient-stops", a]
        default: break
        }
        return (["--terminal-background-color", String(format: "%06x", background)] + parts).joined(separator: " ")
    }
}

enum Themes {
    static let all: [Theme] = [
        Theme(id: "omarchy", name: "Omarchy", background: 0x000000, foreground: 0xF0F0F0, stops: [], accents: []),
        Theme(id: "tokyo-night", name: "Tokyo Night", background: 0x1A1B26, foreground: 0xC0CAF5,
              stops: ["7aa2f7", "bb9af7", "7dcfff"], accents: ["f7768e", "e0af68", "9ece6a", "7dcfff"]),
        Theme(id: "catppuccin", name: "Catppuccin", background: 0x1E1E2E, foreground: 0xCDD6F4,
              stops: ["cba6f7", "f5c2e7", "89dceb"], accents: ["f38ba8", "fab387", "a6e3a1", "89b4fa"]),
        Theme(id: "gruvbox", name: "Gruvbox", background: 0x282828, foreground: 0xEBDBB2,
              stops: ["cc241d", "d79921", "b8bb26"], accents: ["fb4934", "fe8019", "fabd2f", "8ec07c"]),
        Theme(id: "nord", name: "Nord", background: 0x2E3440, foreground: 0xECEFF4,
              stops: ["5e81ac", "81a1c1", "88c0d0"], accents: ["bf616a", "ebcb8b", "a3be8c", "8fbcbb"]),
        Theme(id: "everforest", name: "Everforest", background: 0x2D353B, foreground: 0xD3C6AA,
              stops: ["83c092", "a7c080", "dbbc7f"], accents: ["e67e80", "e69875", "dbbc7f", "7fbbb3"]),
        Theme(id: "kanagawa", name: "Kanagawa", background: 0x1F1F28, foreground: 0xDCD7BA,
              stops: ["957fb8", "7e9cd8", "e6c384"], accents: ["c34043", "ffa066", "98bb6c", "7fb4ca"]),
        Theme(id: "rose-pine", name: "Rosé Pine", background: 0x191724, foreground: 0xE0DEF4,
              stops: ["eb6f92", "c4a7e7", "f6c177"], accents: ["eb6f92", "ebbcba", "31748f", "9ccfd8"]),
        Theme(id: "matte-black", name: "Matte Black", background: 0x121212, foreground: 0xBEBEBE,
              stops: ["5c5c5c", "bebebe", "f0a500"], accents: ["8a8a8d", "bebebe", "f0a500", "ffffff"]),
    ]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }
}
