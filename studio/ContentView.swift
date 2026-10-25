import SwiftUI
import ScreenSaver

struct ContentView: View {
    @EnvironmentObject private var wallpaper: Wallpaper
    @ObservedObject private var updates = Updates.shared
    @State private var editingLogo = false
    @State private var draft: EffectConfig
    @State private var focused: String?          // effect previewed on its own
    @State private var hovered: String?
    @State private var screensaver = Screensaver.currentConfig
    @State private var screensaverInstalled = Screensaver.installed != nil
    @State private var message: String?
    @AppStorage("tutorialSeen") private var tutorialSeen = false
    @State private var showTutorial = false
    private let snapshotMode: Bool

    /// `snapshot`: a fixed selection, focus and tutorial state for README screenshots; nothing is saved.
    init(snapshot: (draft: EffectConfig, focused: String?, tutorial: Bool)? = nil) {
        _draft = State(initialValue: snapshot?.draft ?? Store.draft)
        _focused = State(initialValue: snapshot?.focused)
        _showTutorial = State(initialValue: snapshot?.tutorial ?? false)
        _editingLogo = State(initialValue: snapshot != nil && ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_EDITOR"] != nil)
        snapshotMode = snapshot != nil
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                effectList.frame(width: 320)
                Rectangle().fill(Color.ink.opacity(0.12)).frame(width: 1)
                detail.padding(20)
            }
            if editingLogo {
                CustomLogoEditor(draft: $draft, isPresented: $editingLogo)
                    .transition(.opacity)
                    .zIndex(1)
            }
            if showTutorial {
                TutorialOverlay(isPresented: $showTutorial)
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

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewView(effects: previewEffects, config: draft)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.25), lineWidth: 1.5))
                .layoutPriority(-1)
            Text(focused.map { id in "Previewing \(Catalog.effects.first { $0.id == id }!.title) — click it again to preview your selection" }
                 ?? (draft.effects.count == 1 ? "Previewing your selection" : "Previewing your selection in random order"))
                .foregroundStyle(.secondary)

            options

            HStack(spacing: 12) {
                BigActionButton(title: "Use as Screensaver", subtitle: "Plays when your Mac is idle",
                                icon: .moon) { applyScreensaver() }
                BigActionButton(title: "Use as Wallpaper", subtitle: "Lives on your desktop",
                                icon: .storm) { applyWallpaper() }
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
            if let update = updates.available {
                statusRow(title: "Update", value: "Applarchy \(update.version) is available") {
                    Button("Download…") { NSWorkspace.shared.open(update.url) }.buttonStyle(PixelButtonStyle())
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
                    ("apple", EffectConfig.logoTitle("apple")),
                    ("custom", EffectConfig.logoTitle("custom")),
                ])
                .frame(width: 470)
                if draft.logo == "custom" {
                    Button("Edit…") { editingLogo = true }.buttonStyle(PixelButtonStyle())
                }
            }
            optionRow("Theme") {
                HStack(spacing: 6) {
                    ForEach(Themes.all) { theme in
                        ThemeSwatch(theme: theme, selected: draft.theme == theme.id) { draft.theme = theme.id }
                    }
                }
                Text(Themes.named(draft.theme).name).foregroundStyle(.secondary)
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
                               options: [("30", "30 FPS"), ("15", "15 FPS")])
                    .frame(width: 190)
                Toggle("Pause on battery", isOn: $wallpaper.options.pauseOnBattery).toggleStyle(PixelCheckboxStyle())
                Toggle("Pause in Low Power Mode", isOn: $wallpaper.options.pauseInLowPowerMode).toggleStyle(PixelCheckboxStyle())
            }
        }
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

    private func applyScreensaver() {
        do {
            switch try Screensaver.apply(draft) {
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
        wallpaper.start(draft)
        message = "Wallpaper set. It runs behind your desktop icons and starts again when you log in."
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
                || view.themeID != config.theme || view.clockStyle != config.clockStyle || view.customLogoText != config.customLogo else { return }
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
        view.holdSeconds = 1.5
        view.followsScreensaverStop = false
        // Offscreen image at Retina scale: far cheaper than redrawing the window. (Window
        // snapshots draw the view directly, since they can't capture layer contents.)
        view.bitmapScale = ProcessInfo.processInfo.environment["OMARCHY_PREVIEW_DIRECT"] == nil ? 2 : nil
        view.animationTimeInterval = 1.0 / 30.0
    }
}
