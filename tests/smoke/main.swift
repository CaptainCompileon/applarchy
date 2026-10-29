import AppKit

// Smoke test: every effect in every theme through the engine's C API, built exactly as the app
// builds them (Catalog, Theme.command(for:)), plus a few canvas sizes and logos. An effect that
// doesn't build would silently be replaced by a random one in the app, so that's a failure here,
// as are effects that play no frames or don't finish. Built and run by scripts/test.sh.

func run(_ command: String, logo: String, width: Int32, height: Int32) -> String? {
    guard let saver = logo.withCString({ t in command.withCString { ttfx_saver_new_named(t, width, height, 7, $0) } }) else {
        return "doesn't build"
    }
    defer { ttfx_saver_free(saver) }
    // The app's own caps: 200,000 engine frames for the wallpaper (a ten-minute storm), 30,000 otherwise.
    let cap = command.contains("--storm-time") ? 200_000 : 30_000
    var len = 0, frames = 0
    while frames < cap, ttfx_saver_next(saver, &len) != nil { frames += 1 }
    if frames == 0 { return "plays no frames" }
    if frames == cap { return "doesn't finish in \(cap) frames" }
    return nil
}

let commands = Catalog.allIDs + ["thunderstorm --storm-time 600"]   // as the wallpaper plays it alone
let small = LogoArt.text(named: "apple-small") ?? "x", big = LogoArt.text(named: "apple") ?? "x"
var failures: [String] = [], runs = 0
let start = Date()

// Every effect in every theme, on a laptop-sized grid (16:10) with the default logo.
for theme in Themes.all {
    for effect in commands {
        runs += 1
        if let why = run(theme.command(for: effect), logo: small, width: 139, height: 46) {
            failures.append("\(effect) in \(theme.id): \(why)")
        }
    }
}
// Every effect on other grids and logos (default theme): the in-app preview, an ultrawide,
// a portrait screen, the big logo, a custom text logo.
let theme = Themes.named("omarchy")
for (w, h, logo, label) in [(144, 42, small, "preview"), (216, 46, small, "ultrawide"), (139, 128, small, "portrait"),
                            (139, 46, big, "big logo"), (139, 46, "▄█▀ HELLO\n█▄▀ WORLD", "custom logo")] {
    for effect in commands {
        runs += 1
        if let why = run(theme.command(for: effect), logo: logo, width: Int32(w), height: Int32(h)) {
            failures.append("\(effect), \(label) (\(w)x\(h)): \(why)")
        }
    }
}

print(String(format: "%d runs (%d effects × %d themes, plus 5 grids/logos) in %.1f s", runs, commands.count, Themes.all.count, Date().timeIntervalSince(start)))
if failures.isEmpty {
    print("all passed")
} else {
    print("\(failures.count) failed:\n  " + failures.joined(separator: "\n  "))
    exit(1)
}
