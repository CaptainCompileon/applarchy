import SwiftUI
import ScreenSaver

struct ContentView: View {
    @EnvironmentObject private var wallpaper: Wallpaper
    @ObservedObject private var updates = Updates.shared
    @State private var editingLogo = false
    @State private var showingLogoLibrary = false
    @State private var editingTheme = false
    @State private var draft: EffectConfig
    @State private var focused: String?          // effect previewed on its own
    @State private var hovered: String?
    @State private var screensaver = Screensaver.currentConfig
    @State private var screensaverInstalled = Screensaver.installed != nil
    @State private var message: String?
    @AppStorage("tutorialSeen") private var tutorialSeen = false
    /// "smooth": one look for screensaver, lock screen and desktop; "custom": each set separately.
    /// Remembered once chosen; until then, see initialMode.
    @AppStorage("mode") private var mode = "smooth"
    @State private var showTutorial = false
    private let snapshotMode: Bool

    /// `snapshot`: a fixed selection, focus and tutorial state for README screenshots; nothing is saved.
    init(snapshot: (draft: EffectConfig, focused: String?, tutorial: Bool)? = nil) {
        _draft = State(initialValue: snapshot?.draft ?? Store.draft)
        _focused = State(initialValue: snapshot?.focused)
        _showTutorial = State(initialValue: snapshot?.tutorial ?? false)
        _editingLogo = State(initialValue: snapshot != nil && ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_EDITOR"] != nil)
        _showingLogoLibrary = State(initialValue: snapshot != nil && ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_LIBRARY"] != nil)
        _editingTheme = State(initialValue: snapshot != nil && ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_THEME_EDITOR"] != nil)
        if snapshot != nil, let store = UserDefaults(suiteName: "com.applarchy.app.snapshot") {   // screenshots: don't touch real settings
            store.set(ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_MODE"] ?? "custom", forKey: "mode")
            _mode = AppStorage(wrappedValue: "custom", "mode", store: store)
        } else if UserDefaults.standard.object(forKey: "mode") == nil {
            UserDefaults.standard.set(Self.initialMode, forKey: "mode")
        }
        snapshotMode = snapshot != nil
    }

    /// The mode to open in before one has been chosen: what's already set up, if anything
    /// (Smooth Mode on, or a 2.0-style separate wallpaper or screensaver), else Smooth Mode.
    private static var initialMode: String {
        if Store.wallpaper?.smoothTransition == true || Screensaver.currentConfig?.smoothTransition == true { return "smooth" }
        if Store.wallpaper != nil || Screensaver.installed != nil { return "custom" }
        return "smooth"
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                effectList.frame(width: 320)
                Rectangle().fill(Color.ink.opacity(0.12)).frame(width: 1)
                detail.padding(20)
            }
            if editingTheme {
                CustomThemeEditor(draft: $draft, isPresented: $editingTheme)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if editingLogo {
                CustomLogoEditor(draft: $draft, isPresented: $editingLogo)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if showingLogoLibrary {
                LogoLibraryView(isPresented: $showingLogoLibrary, current: draft.logo == "custom" ? draft.customLogo : nil) { picked in
                    draft.customLogo = picked
                    draft.logo = "custom"
                }
                .transition(.opacity)
                .zIndex(1)
            }
            if showTutorial {
                TutorialOverlay(isPresented: $showTutorial)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            } else if let release = updates.prompt {
                UpdatePrompt(release: release, installed: updates.current,
                             download: { withAnimation(.easeOut(duration: 0.15)) { updates.download() } },
                             later: { withAnimation(.easeOut(duration: 0.15)) { updates.dismiss() } })
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .frame(minWidth: 980, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
        .font(Pixel.body)
        .tint(.ink)
        .noFocusRing()
        .onAppear { if !tutorialSeen && !snapshotMode { withAnimation(.easeOut(duration: 0.3).delay(0.35)) { showTutorial = true } } }
        .onChange(of: showTutorial) { if !$0 && !snapshotMode { tutorialSeen = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showTutorial)) { _ in withAnimation(.easeOut(duration: 0.25)) { showTutorial = true } }
        .onChange(of: draft) { if !snapshotMode { Store.draft = $0 } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    // MARK: effect list

    private var effectList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("EFFECTS").font(Pixel.title)
                Button("?") { withAnimation(.easeOut(duration: 0.25)) { showTutorial = true } }
                    .buttonStyle(PixelButtonStyle()).help("Show the tutorial")
                Spacer()
                Button("ALL") { draft.effects = Catalog.allIDs }.buttonStyle(PixelButtonStyle())
                Button("NONE") { draft.effects = [] }.buttonStyle(PixelButtonStyle())
            }
            .padding([.horizontal, .top], 12).padding(.bottom, 10)
            Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 1)
            PixelScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Catalog.effects) { effect in
                        effectRow(effect)
                        Rectangle().fill(Color.ink.opacity(0.08)).frame(height: 1)
                    }
                }
            }
            Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 1)
            Text("\(draft.effects.count)/\(Catalog.effects.count) selected · click a name to preview")
                .foregroundStyle(.secondary).padding(12)
        }
    }

    /// A flat row: pixel checkbox, name and description. The row being previewed
    /// is inverted (ink fill, paper text); others tint faintly on hover.
    private func effectRow(_ effect: EffectInfo) -> some View {
        let previewing = focused == effect.id
        let ink: Color = previewing ? .paper : .ink
        return HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: selected(effect.id))
                .toggleStyle(PixelCheckboxStyle(ink: ink)).labelsHidden()
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(effect.title).foregroundStyle(ink)
                Text(effect.summary).foregroundStyle(ink.opacity(0.6)).lineLimit(3).lineSpacing(2)
            }
            Spacer(minLength: 0)
            if previewing { Text("▶").foregroundStyle(ink) }
        }
        .font(Pixel.body)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(previewing ? Color.ink : (hovered == effect.id ? Color.ink.opacity(0.06) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { focused = previewing ? nil : effect.id }
        .onHover { inside in
            if inside { hovered = effect.id } else if hovered == effect.id { hovered = nil }
        }
    }

    private func selected(_ id: String) -> Binding<Bool> {
        Binding(
            get: { draft.effects.contains(id) },
            set: { on in
                var set = Set(draft.effects)
                if on { set.insert(id) } else { set.remove(id) }
                draft.effects = Catalog.allIDs.filter(set.contains)   // keep catalogue order
            })
    }

    // MARK: detail

    private var previewEffects: [String] {
        if let focused { return [focused] }
        return draft.effects.isEmpty ? Catalog.allIDs : draft.effects
    }

    private var smoothActive: Bool { wallpaper.config?.smoothTransition == true }

    private var modePicker: some View {
        HStack(spacing: 12) {
            ModeCard(title: "Smooth Mode", selected: mode == "smooth",
                     detail: "One look everywhere: screensaver, lock screen and desktop. The animation carries on as you unlock and settles into the logo.") {
                withAnimation(.easeOut(duration: 0.15)) { mode = "smooth" }
            }
            ModeCard(title: "Custom", selected: mode == "custom",
                     detail: "Set the screensaver and the wallpaper separately, with every option.") {
                withAnimation(.easeOut(duration: 0.15)) { mode = "custom" }
            }
        }
        .fixedSize(horizontal: false, vertical: true)   // both cards as tall as the taller one
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            modePicker
            PreviewView(effects: previewEffects, config: draft)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.25), lineWidth: 1.5))
                .layoutPriority(-1)
            Text(focused.map { id in "Previewing \(Catalog.effects.first { $0.id == id }!.title) — click it again to preview your selection" }
                 ?? (draft.effects.count == 1 ? "Previewing your selection" : "Previewing your selection in random order"))
                .foregroundStyle(.secondary)

            options

            Group {
                if mode == "smooth" {
                    BigActionButton(title: smoothActive ? "Update Smooth Mode" : "Apply Smooth Mode",
                                    subtitle: "Screensaver, lock screen and desktop, all in one",
                                    icon: .moon) { applySmooth() }
                } else {
                    HStack(spacing: 12) {
                        BigActionButton(title: "Use as Screensaver", subtitle: "Plays when your Mac is idle",
                                        icon: .moon) { applyScreensaver() }
                        BigActionButton(title: "Use as Wallpaper", subtitle: "Lives on your desktop",
                                        icon: .storm) { applyWallpaper() }
                    }
                }
            }
            .padding(.top, 2)
            .disabled(draft.effects.isEmpty)
            if draft.effects.isEmpty { Text("Select at least one effect.").foregroundStyle(.secondary) }

            if Bundle.main.bundlePath.contains("/AppTranslocation/") {
                Text("! Move Applarchy to your Applications folder and open it from there, so it can start at login.")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Text(message).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 1)
            if smoothActive, let config = wallpaper.config {
                statusRow(title: "Smooth Mode", value: config.summary.replacingOccurrences(of: ", smooth", with: "")) {
                    Button("Screen Saver Settings…") { Screensaver.openSettings() }.buttonStyle(PixelButtonStyle())
                    Button("Turn Off") { turnOffSmooth() }.buttonStyle(PixelButtonStyle())
                }
            } else {
                statusRow(title: "Screensaver",
                          value: screensaver?.summary ?? (screensaverInstalled ? "Installed, all effects" : "Not installed")) {
                    Button("Screen Saver Settings…") { Screensaver.openSettings() }.buttonStyle(PixelButtonStyle())
                }
                statusRow(title: "Wallpaper", value: wallpaperStatus) {
                    if wallpaper.isRunning {
                        Button(wallpaper.paused ? "Resume" : "Pause") { wallpaper.paused.toggle() }.buttonStyle(PixelButtonStyle())
                        Button("Turn Off") { wallpaper.stop() }.buttonStyle(PixelButtonStyle())
                    }
                }
            }
            if let update = updates.available {
                statusRow(title: "Update", value: "Applarchy \(update.version) is available") {
                    Button("Download…") { updates.download() }.buttonStyle(PixelButtonStyle(prominent: true))
                }
            }
        }
    }

    private var wallpaperStatus: String {
        guard let config = wallpaper.config else { return "Off" }
        if wallpaper.paused { return config.summary + " (paused)" }
        if let reason = wallpaper.powerPause { return config.summary + " (paused: \(reason))" }
        return config.summary
    }

    // MARK: options

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            optionRow("Logo") {
                PixelSegmented(selection: Binding(
                    get: { draft.logo },
                    set: { new in
                        if new == "custom" && draft.customLogo == nil { editingLogo = true } else { draft.logo = new }
                    }), options: [
                    ("apple-small", EffectConfig.logoTitle("apple-small")),
                    ("custom", EffectConfig.logoTitle("custom")),
                ])
                .frame(width: 300)
                if draft.logo == "custom" {
                    Button("Edit…") { editingLogo = true }.buttonStyle(PixelButtonStyle())
                }
                Button("My Logos…") { showingLogoLibrary = true }.buttonStyle(PixelButtonStyle())   // also where IMPORT… is
            }
            optionRow("Theme") {
                HStack(spacing: 6) {
                    ForEach(Themes.all) { theme in
                        ThemeSwatch(theme: theme, selected: draft.theme == theme.id) { draft.theme = theme.id }
                    }
                    // Your own: its colours once made; until then a "+" that opens the editor.
                    ThemeSwatch(theme: (draft.customTheme ?? CustomTheme(Themes.named(draft.theme))).theme,
                                selected: draft.theme == "custom", placeholder: draft.customTheme == nil) {
                        if draft.customTheme == nil { editingTheme = true } else { draft.theme = "custom" }
                    }
                }
                Text(Themes.named(draft.theme, custom: draft.customTheme).name).foregroundStyle(.secondary)
                if draft.theme == "custom" {
                    Button("Edit…") { editingTheme = true }.buttonStyle(PixelButtonStyle())
                }
            }
            optionRow("Clock") {
                Toggle("Show", isOn: $draft.showClock).toggleStyle(PixelCheckboxStyle())
                Group {
                    Toggle("Date", isOn: $draft.showDate).toggleStyle(PixelCheckboxStyle())
                    PixelSegmented(selection: $draft.hourCycle, options: [("auto", "AUTO"), ("12", "12H"), ("24", "24H")])
                        .frame(width: 200)
                    PixelSegmented(selection: Binding(get: { draft.clockLarge ? "large" : "small" },
                                                      set: { draft.clockLarge = $0 == "large" }),
                                   options: [("small", "SMALL"), ("large", "LARGE")])
                        .frame(width: 170)
                }
                .disabled(!draft.showClock)
                .opacity(draft.showClock ? 1 : 0.35)
            }
            optionRow("Wallpaper") {
                PixelSegmented(selection: Binding(get: { "\(wallpaper.options.fps)" },
                                                  set: { wallpaper.options.fps = Int($0) ?? 30 }),
                               options: [("\(WallpaperOptions.auto)", "AUTO"), ("120", "120"), ("60", "60"), ("30", "30"), ("15", "15")])
                    .frame(width: 330)
                Text(fpsNote).foregroundStyle(.secondary)
            }
            optionRow("") {
                Toggle("Pause on battery", isOn: $wallpaper.options.pauseOnBattery).toggleStyle(PixelCheckboxStyle())
                Toggle("Pause in Low Power Mode", isOn: $wallpaper.options.pauseInLowPowerMode).toggleStyle(PixelCheckboxStyle())
            }
        }
    }

    /// After the frame-rate picker: "FPS", or for auto what it comes to on the displays.
    private var fpsNote: String {
        guard wallpaper.options.fps == WallpaperOptions.auto else { return "FPS" }
        var seen = Set<Int>()
        let rates = NSScreen.screens.map { wallpaper.options.rate(displayHz: $0.maximumFramesPerSecond) }
            .filter { seen.insert($0).inserted }
        return "= " + (rates.isEmpty ? "60" : rates.map(String.init).joined(separator: "/")) + " FPS"
    }

    private func optionRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Text(title.uppercased()).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func statusRow<Buttons: View>(title: String, value: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack {
            Text(title.uppercased() + ":").frame(width: 120, alignment: .leading)
            Text(value).foregroundStyle(.secondary)
            Spacer()
            buttons()
        }
    }

    // MARK: actions

    /// Smooth mode: the screensaver keeps playing on the lock screen and announces
    /// its effects; the desktop picture (shown on the lock screen) becomes a still of the
    /// logo; the wallpaper finishes the last animation after you log in, then holds.
    private func applySmooth() {
        var config = draft
        config.smoothTransition = true
        wallpaper.start(config)
        LockScreen.apply(config)
        do {
            switch try Screensaver.apply(config) {
            case .updated:
                message = "Smooth mode is on: the screensaver, lock screen and desktop now share one look."
            case .installerOpened:
                message = "Almost there: click Install in the dialog (and Replace, if asked), then choose Applarchy in Screen Saver settings."
            }
        } catch {
            message = "Couldn't update the screensaver: \(error.localizedDescription)"
        }
        refresh()
    }

    private func turnOffSmooth() {
        wallpaper.stop()
        LockScreen.restore()
        Screensaver.setSmooth(false)
        message = "Smooth mode is off. Your previous wallpaper and lock screen are back."
        refresh()
    }

    /// Custom mode: leaving smooth mode puts the wallpaper and lock screen back.
    private func leaveSmooth() {
        guard smoothActive else { return }
        LockScreen.restore()
    }

    private func applyScreensaver() {
        var config = draft
        config.smoothTransition = false
        if smoothActive { leaveSmooth(); wallpaper.stop() }
        do {
            switch try Screensaver.apply(config) {
            case .updated:
                message = "Screensaver updated. It takes effect the next time the screensaver starts."
            case .installerOpened:
                message = "Click Install in the dialog that opened (and Replace, if asked). Then choose Applarchy in Screen Saver settings."
            }
        } catch {
            message = "Couldn't update the screensaver: \(error.localizedDescription)"
        }
        refresh()
    }

    private func applyWallpaper() {
        var config = draft
        config.smoothTransition = false
        if smoothActive { leaveSmooth(); Screensaver.setSmooth(false) }
        wallpaper.start(config)
        message = "Wallpaper set. It runs behind your desktop icons and starts again when you log in."
        refresh()
    }

    private func refresh() {
        screensaver = Screensaver.currentConfig
        screensaverInstalled = Screensaver.installed != nil
    }
}

/// A live preview: the same view the screensaver and wallpaper use.
struct PreviewView: NSViewRepresentable {
    let effects: [String]
    var config = EffectConfig.default

    init(effects: [String], config: EffectConfig) {
        self.effects = effects
        self.config = config
    }

    init(effects: [String], logo: String, showClock: Bool) {
        self.effects = effects
        config = EffectConfig(effects: effects, logo: logo, showClock: showClock)
    }

    func makeNSView(context: Context) -> StudioEffectView {
        let view = StudioEffectView(frame: NSRect(x: 0, y: 0, width: 560, height: 350), isPreview: true)!
        configure(view)
        view.startAnimation()
        return view
    }

    func updateNSView(_ view: StudioEffectView, context: Context) {
        guard view.effectCommands != effects || view.logoName != config.logo || view.showsClock != config.showClock
                || view.themeID != config.theme || view.clockStyle != config.clockStyle || view.customLogoText != config.customLogo
                || view.customTheme != config.customTheme else { return }
        view.stopAnimation()
        configure(view)
        view.startAnimation()
    }

    static func dismantleNSView(_ view: StudioEffectView, coordinator: ()) { view.stopAnimation() }

    private func configure(_ view: StudioEffectView) {
        view.effectCommands = effects
        view.customLogoText = config.customLogo
        view.logoName = config.logo
        view.showsClock = config.showClock
        view.clockStyle = config.clockStyle
        view.themeID = config.theme
        view.customTheme = config.customTheme
        view.holdSeconds = 1.5
        view.followsScreensaverStop = false
        // Offscreen image at Retina scale: far cheaper than redrawing the window. (Window
        // snapshots draw the view directly, since they can't capture layer contents.)
        view.bitmapScale = ProcessInfo.processInfo.environment["OMARCHY_PREVIEW_DIRECT"] == nil ? 2 : nil
        view.animationTimeInterval = 1.0 / 30.0
    }
}
