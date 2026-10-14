import Foundation

/// What to play: a set of effects (shuffled, each once before repeating), the
/// logo size, and (screensaver only) whether to draw the pixel clock.
struct EffectConfig: Codable, Equatable {
    var effects: [String]
    var logo: String          // "apple-small" (Chill Guy) or "apple" (Apple Evangelist)
    var showClock: Bool

    static let `default` = EffectConfig(effects: Catalog.allIDs, logo: "apple-small", showClock: true)

    static func logoTitle(_ logo: String) -> String { logo == "apple-small" ? "Chill Guy" : "Apple Evangelist" }

    var summary: String {
        let names: String
        if Set(effects) == Set(Catalog.allIDs) { names = "All \(effects.count) effects" }
        else if effects.count == 1 { names = Catalog.effects.first { $0.id == effects[0] }?.title ?? effects[0] }
        else { names = "\(effects.count) effects" }
        return names + ", " + Self.logoTitle(logo)
    }

    /// The ttfx commands to cycle through. As a wallpaper, a lone thunderstorm
    /// storms for 10 minutes at a time instead of 12 seconds.
    func commands(forWallpaper: Bool) -> [String] {
        if forWallpaper, effects == ["thunderstorm"] { return ["thunderstorm --storm-time 600"] }
        return effects
    }
}

/// The app's saved state.
enum Store {
    private static let defaults = UserDefaults.standard

    static var wallpaper: EffectConfig? {
        get { defaults.data(forKey: "wallpaper").flatMap { try? JSONDecoder().decode(EffectConfig.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "wallpaper") }
    }

    /// The selection last shown in the window.
    static var draft: EffectConfig {
        get { defaults.data(forKey: "draft").flatMap { try? JSONDecoder().decode(EffectConfig.self, from: $0) } ?? .default }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "draft") }
    }
}
