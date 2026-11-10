import AppKit

// Unit tests for the app's own logic, the parts that run without a screen: Smooth Mode's handoff
// arithmetic, the shared timeline, theme commands, saved settings, logo files and version
// comparison. Built and run by scripts/test.sh, with the effect view compiled as the app compiles
// it (StudioEffectView).

var failures: [String] = [], checks = 0

func expect(_ ok: @autoclosure () -> Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok() { failures.append("line \(line): \(what)") }
}

typealias Handoff = StudioEffectView.Handoff

// MARK: Smooth Mode's handoff

do {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let size = CGSize(width: 1512, height: 982)
    let playing = Handoff(command: "--terminal-background-color 1a1b26 matrix --rain-color-gradient f7768e e0af68",
                          seed: 42, startedAt: start, size: size)
    expect(Handoff(payload: playing.payload) == playing, "a handoff survives its payload")
    var settling = playing
    settling.settleAt = start.addingTimeInterval(2.5)
    expect(Handoff(payload: settling.payload) == settling, "a settling handoff survives its payload")
    expect(Handoff(payload: "not a payload") == nil, "a malformed payload is refused")
    expect(Handoff(payload: "1|2|3x4") == nil, "a short payload is refused")

    expect(playing.frame(at: start.addingTimeInterval(-5)) == 0, "no frames before the effect starts")
    expect(playing.frame(at: start.addingTimeInterval(1)) == 120, "120 engine frames a second")
    expect(playing.glideStart(frames: 600) == nil, "no glide before settling")

    // Settling: the same up to the settle moment, faster and speeding up after it.
    expect(settling.frame(at: start.addingTimeInterval(2.5)) == 300, "settling changes nothing before it begins")
    let after = settling.frame(at: start.addingTimeInterval(3.5))
    expect(after == 300 + Int(StudioEffectView.settledFrames(after: 1)), "one second of settling")
    expect(after > playing.frame(at: start.addingTimeInterval(3.5)), "settling is faster than playing")
    var last = 0
    for tenth in 0...100 {
        let n = settling.frame(at: start.addingTimeInterval(Double(tenth) / 10))
        expect(n >= last, "frames never go back (at \(Double(tenth) / 10) s)")
        last = n
    }

    // date(ofFrame:) is frame(at:) backwards: the first moment the effect is at that frame.
    for n in [1, 120, 299, 300, 301, 1000, 5000] {
        for h in [playing, settling] {
            let t = h.date(ofFrame: n)
            expect(h.frame(at: t) >= n && h.frame(at: t.addingTimeInterval(-0.01)) < n, "date(ofFrame: \(n)) is when frame \(n) is reached")
        }
    }
    // The glide starts when the effect is over, but not before settling began.
    expect(settling.glideStart(frames: 100) == settling.settleAt, "an effect over before settling glides from the settle moment")
    expect(settling.glideStart(frames: 2000).map { $0 > settling.settleAt! } == true, "an effect still playing glides once it's over")

    expect(StudioEffectView.settledFrames(after: 0) == 0, "settling starts from the frame it was at")
    expect(StudioEffectView.displayRate(hz: 0) == 60 && StudioEffectView.displayRate(hz: 180) == 120
           && StudioEffectView.displayRate(hz: 50) == 50, "the display's rate, capped at 120, 60 when unknown")
}

// MARK: the shared timeline

do {
    func view(_ effect: String) -> StudioEffectView {
        let v = StudioEffectView(frame: NSRect(x: 0, y: 0, width: 800, height: 500), isPreview: false)!
        v.effectCommands = [effect]
        v.respectsReduceMotion = false          // whatever this Mac's setting: the test names its effects
        v.followsScreensaverStop = false
        return v
    }
    if ProcessInfo.processInfo.environment["OMARCHY_EFFECT"] == nil {
        // The wallpaper's screens: the first starts an effect, the second joins it.
        let first = view("matrix"), second = view("wipe")
        first.startAnimation()
        second.startAnimation()
        expect(first.clockedCommand == "matrix", "the first view starts its own effect")
        expect(second.clockedCommand == "matrix", "a view joining the timeline plays what's playing, not its own selection")

        // The full-screen preview: a timeline of its own, so it starts on its selection
        // and leaves the wallpaper's alone.
        let own = StudioEffectView.Timeline()
        let preview = view("wipe"), otherScreen = view("wipe")
        preview.timeline = own
        otherScreen.timeline = own
        preview.startAnimation()
        otherScreen.startAnimation()
        expect(preview.clockedCommand == "wipe" && otherScreen.clockedCommand == "wipe", "a view on its own timeline plays its own selection")
        expect(first.clockedCommand == "matrix", "and the shared timeline's effect carries on")

        // Once everything has left, the next view starts afresh.
        for v in [first, second, preview, otherScreen] { v.stopAnimation() }
        let later = view("wipe")
        later.startAnimation()
        expect(later.clockedCommand == "wipe", "an empty timeline starts the next view's own effect")
        later.stopAnimation()
    }
}

// MARK: themes

do {
    let omarchy = Themes.named("omarchy")
    expect(omarchy.command(for: "thunderstorm --storm-time 600") == "thunderstorm --storm-time 600", "Omarchy keeps ttfx's own colours")
    expect(Themes.named("no such theme").id == "omarchy", "an unknown theme falls back to Omarchy")

    let nord = Themes.named("nord")
    let beams = nord.command(for: "beams")
    expect(beams.hasPrefix("--terminal-background-color 2e3440 beams "), "global options come before the effect's name")
    expect(beams.contains("--final-gradient-stops 5e81ac 81a1c1 88c0d0") && beams.contains("--beam-gradient-stops bf616a"), "the gradient and the accents")
    expect(nord.command(for: "synthgrid").contains("--text-gradient-stops"), "synthgrid names its gradient differently")

    // A custom theme from a hand-edited config: no accents, or colours the engine can't read.
    var custom = CustomTheme(nord)
    custom.accents = []
    for effect in Catalog.allIDs {
        let command = custom.theme.command(for: effect)
        expect(!command.hasSuffix("-stops ") && !command.hasSuffix("-colors ") && !command.contains("-color  "), "\(effect): no option without a value")
    }
    custom.accents = ["zzzzzz", "12345", "+12345", "a3be8c"]
    custom.stops = ["not a colour"]
    expect(custom.theme.accents == ["a3be8c"] && custom.theme.stops.isEmpty, "only rrggbb colours reach the engine")
    expect(custom.theme.command(for: "rain") == "rain", "without a gradient the effect keeps its own colours")
}

// MARK: saved settings

do {
    // Settings saved by 2.0 have only these keys; newer ones take their defaults.
    let old = Data(#"{"effects": ["matrix", "rain"], "logo": "apple", "showClock": false}"#.utf8)
    if let config = try? JSONDecoder().decode(EffectConfig.self, from: old) {
        expect(config.effects == ["matrix", "rain"] && !config.showClock, "old settings keep what they had")
        expect(config.logo == "apple-small", "the retired logo becomes Chill Guy")
        expect(config.theme == "omarchy" && config.hourCycle == "auto" && config.showDate && !config.clockLarge
               && config.customLogo == nil && config.customTheme == nil && !config.smoothTransition && config.pauseSeconds == 3,
               "newer keys take their defaults")
    } else {
        expect(false, "settings saved by an older version still load")
    }
    var config = EffectConfig.default
    config.theme = "custom"
    config.customTheme = CustomTheme(Themes.named("gruvbox"))
    config.customLogo = "▄█▀\n"
    config.smoothTransition = true
    config.pauseSeconds = 10
    let again = (try? JSONEncoder().encode(config)).flatMap { try? JSONDecoder().decode(EffectConfig.self, from: $0) }
    expect(again == config, "settings survive saving and loading")
    expect(EffectConfig(effects: ["thunderstorm"], logo: "apple-small", showClock: true).commands(forWallpaper: true) == ["thunderstorm --storm-time 600"],
           "a lone thunderstorm storms on as a wallpaper")
    expect(WallpaperOptions().rate(displayHz: 120) == 30 && WallpaperOptions(fps: WallpaperOptions.auto).rate(displayHz: 120) == 120, "the picker's rate, or the display's for Auto")
}

// MARK: logo files

do {
    expect(LogoFile.clean("\r\n\r\n  ▄█▀  \r\n\r\n█▄▀\t \r\n\r\n") == "  ▄█▀\n\n█▄▀\n", "tidied: line endings, trailing spaces, blank lines around")
    expect(LogoFile.clean(" \n\n ") == nil, "nothing at all is no logo")
    expect(LogoFile.clean(String(repeating: "█\n", count: LogoFile.maxLines)) != nil
           && LogoFile.clean(String(repeating: "█\n", count: LogoFile.maxLines + 1)) == nil, "at most maxLines lines")
    expect(LogoFile.clean(String(repeating: "█", count: LogoFile.maxColumns)) != nil
           && LogoFile.clean(String(repeating: "█", count: LogoFile.maxColumns + 1)) == nil, "at most maxColumns columns")
    expect(LogoFile.clean("█\u{1B}[31m█") == nil, "escape sequences aren't text art")

    let arts = ["▄█▀\n", "█▄▀\n█\n"]
    expect((try? LogoFile.logos(in: LogoFile.data(arts))) == arts, "an exported file imports as it was")
    expect((try? LogoFile.logos(in: Data("▄█▀ HELLO".utf8))) == ["▄█▀ HELLO\n"], "a plain text file is one logo")
    expect((try? LogoFile.logos(in: Data(#"{"applarchyLogos": 99, "logos": [{"art": "█"}]}"#.utf8))) == nil, "a newer file format is refused")
    expect((try? LogoFile.logos(in: Data(#"{"some": "json"}"#.utf8))) == nil, "other JSON isn't a logo")
}

// MARK: updates

do {
    expect(Updates.isNewer("2.1", than: "2.0.3") && Updates.isNewer("2.10", than: "2.9") && Updates.isNewer("3.0", than: "2.99.9"), "compared number by number")
    expect(!Updates.isNewer("2.2", than: "2.2") && !Updates.isNewer("2.2.0", than: "2.2") && !Updates.isNewer("2.1.9", than: "2.2"), "the same or older isn't newer")
    let notes = "## What's Changed\n* Smooth Mode by @someone in https://github.com/o/r/pull/12\n- Fixed by hand\n\n**Full Changelog**: https://github.com/o/r/compare/v1...v2"
    expect(Updates.items(notes) == ["Smooth Mode", "Fixed by hand"], "the release notes' pull request titles")

    // GitHub's list of releases → the newest one newer than the installed, and its disk image.
    let digest = String(repeating: "ab", count: 32)
    func dmg(_ version: String, digest: String? = "sha256:" + digest, host: String = "github.com") -> [String: Any] {
        var file: [String: Any] = ["name": "Applarchy-\(version).dmg", "size": 1234,
                                   "browser_download_url": "https://\(host)/CaptainCompileon/applarchy/releases/download/v\(version)/Applarchy-\(version).dmg"]
        if let digest { file["digest"] = digest }
        return file
    }
    func release(_ version: String, _ assets: [[String: Any]], draft: Bool = false, prerelease: Bool = false) -> [String: Any] {
        ["tag_name": "v" + version, "html_url": "https://github.com/CaptainCompileon/applarchy/releases/tag/v" + version,
         "body": "* Change in \(version) by @x in https://github.com/o/r/pull/1", "draft": draft, "prerelease": prerelease, "assets": assets]
    }
    let list = [release("2.8", [dmg("2.8")]), release("3.0", [dmg("3.0")], draft: true), release("2.10", [["name": "notes.txt"], dmg("2.10")]),
                release("2.9", [dmg("2.9")]), release("2.7", [dmg("2.7")]), release("4.0", [dmg("4.0")], prerelease: true)]
    let newest = Updates.release(in: list, newerThan: "2.8")
    expect(newest?.version == "2.10", "the newest published release, drafts and prereleases aside")
    expect(newest?.changes.map(\.version) == ["2.10", "2.9"], "with the changes of every release since the installed one")
    expect(newest?.asset == Updates.Asset(url: URL(string: "https://github.com/CaptainCompileon/applarchy/releases/download/v2.10/Applarchy-2.10.dmg")!,
                                          size: 1234, sha256: digest), "and its disk image, among its other files")
    expect(Updates.release(in: list, newerThan: "2.10") == nil, "nothing newer: no release")

    // A release Applarchy may install by itself needs a checksum and a trusted address.
    expect(Updates.asset(in: release("2.9", [dmg("2.9", digest: nil)])) == nil, "no checksum: only offered as a download")
    expect(Updates.asset(in: release("2.9", [dmg("2.9", digest: "md5:abcd")])) == nil, "another kind of checksum doesn't count")
    expect(Updates.asset(in: release("2.9", [dmg("2.9", digest: "sha256:tooshort")])) == nil, "nor a malformed one")
    expect(Updates.asset(in: release("2.9", [dmg("2.9", host: "example.com")])) == nil, "a file hosted elsewhere isn't installed")
    expect(Updates.asset(in: release("2.9", [])) == nil, "no disk image")
    expect(Updates.isTrustedDownload(URL(string: "https://github.com/CaptainCompileon/applarchy/releases/download/v2.9/Applarchy-2.9.dmg")!), "this repository's release files")
    expect(!Updates.isTrustedDownload(URL(string: "http://github.com/CaptainCompileon/applarchy/releases/download/v2.9/Applarchy-2.9.dmg")!), "not over plain HTTP")
    expect(!Updates.isTrustedDownload(URL(string: "https://github.com/someone/else/releases/download/v2.9/Applarchy-2.9.dmg")!), "not another repository's")
    expect(!Updates.isTrustedDownload(URL(string: "https://github.com.evil.example/CaptainCompileon/applarchy/releases/download/v2.9/a.dmg")!), "not a look-alike host")
    expect(Updates.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256, as GitHub writes it")
}

if failures.isEmpty {
    print("\(checks) checks: all passed")
} else {
    print("\(failures.count) of \(checks) checks failed:\n  " + failures.joined(separator: "\n  "))
    exit(1)
}
