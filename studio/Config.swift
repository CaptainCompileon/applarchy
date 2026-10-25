import Foundation

/// What to play: a set of effects (shuffled, each once before repeating), the
/// logo, the colour theme, and (screensaver only) the pixel clock. The field names
/// are also the keys of the screensaver's config.json.
struct EffectConfig: Codable, Equatable {
    var effects: [String]
    var logo: String                  // "apple-small" (Chill Guy), "apple" (Apple Evangelist) or "custom"
    var showClock: Bool
    var theme = "omarchy"
    var hourCycle = "auto"            // "auto" | "12" | "24"
    var showDate = true
    var clockLarge = false
    var customLogo: String?           // text art, when logo is "custom"
    /// Screensaver keeps playing on the lock screen; the wallpaper finishes its
    /// last animation after you log in and then holds the logo.
    var smoothTransition = false

    static let `default` = EffectConfig(effects: Catalog.allIDs, logo: "apple-small", showClock: true)

    static func logoTitle(_ logo: String) -> String {
        switch logo {
        case "apple-small": return "Chill Guy"
        case "custom": return "Custom"
        default: return "Apple Evangelist"
        }
    }

    var summary: String {
        let names: String
        if Set(effects) == Set(Catalog.allIDs) { names = "All \(effects.count) effects" }
        else if effects.count == 1 { names = Catalog.effects.first { $0.id == effects[0] }?.title ?? effects[0] }
        else { names = "\(effects.count) effects" }
        let themed = theme == "omarchy" ? "" : ", " + Themes.named(theme).name
        return names + ", " + Self.logoTitle(logo) + themed + (smoothTransition ? ", smooth" : "")
    }

    /// The ttfx commands to cycle through. As a wallpaper, a lone thunderstorm
    /// storms for 10 minutes at a time instead of 12 seconds.
    func commands(forWallpaper: Bool) -> [String] {
        if forWallpaper, effects == ["thunderstorm"] { return ["thunderstorm --storm-time 600"] }
        return effects
    }

    var clockStyle: ClockStyle { ClockStyle(hourCycle: hourCycle, showDate: showDate, large: clockLarge) }

    init(effects: [String], logo: String, showClock: Bool) {
        self.effects = effects
        self.logo = logo
        self.showClock = showClock
    }

    // Settings saved by older versions lack the newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        effects = try c.decode([String].self, forKey: .effects)
        logo = try c.decode(String.self, forKey: .logo)
        showClock = try c.decode(Bool.self, forKey: .showClock)
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? "omarchy"
        hourCycle = try c.decodeIfPresent(String.self, forKey: .hourCycle) ?? "auto"
        showDate = try c.decodeIfPresent(Bool.self, forKey: .showDate) ?? true
        clockLarge = try c.decodeIfPresent(Bool.self, forKey: .clockLarge) ?? false
        customLogo = try c.decodeIfPresent(String.self, forKey: .customLogo)
        smoothTransition = try c.decodeIfPresent(Bool.self, forKey: .smoothTransition) ?? false
    }
}

/// Wallpaper-only settings; they apply to the running wallpaper immediately.
struct WallpaperOptions: Codable, Equatable {
    var fps = 30
    var pauseOnBattery = false
    var pauseInLowPowerMode = true
}

/// The app's saved state.
enum Store {
    private static let defaults = UserDefaults.standard

    static var wallpaper: EffectConfig? {
        get { defaults.data(forKey: "wallpaper").flatMap { try? JSONDecoder().decode(EffectConfig.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "wallpaper") }
    }

    static var wallpaperOptions: WallpaperOptions {
        get { defaults.data(forKey: "wallpaperOptions").flatMap { try? JSONDecoder().decode(WallpaperOptions.self, from: $0) } ?? WallpaperOptions() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "wallpaperOptions") }
    }

    /// The selection last shown in the window.
    static var draft: EffectConfig {
        get { defaults.data(forKey: "draft").flatMap { try? JSONDecoder().decode(EffectConfig.self, from: $0) } ?? .default }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "draft") }
    }
}
