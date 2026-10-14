import SwiftUI
import ScreenSaver

struct ContentView: View {
    @EnvironmentObject private var wallpaper: Wallpaper
    @State private var draft: EffectConfig
    @State private var focused: String?          // effect previewed on its own
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
        snapshotMode = snapshot != nil
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                effectList.frame(width: 320)
                Divider()
                detail.padding(20)
            }
            if showTutorial {
                TutorialOverlay(isPresented: $showTutorial)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(1)
            }
        }
        .frame(minWidth: 940, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if !tutorialSeen && !snapshotMode { withAnimation(.easeOut(duration: 0.3).delay(0.35)) { showTutorial = true } } }
        .onChange(of: showTutorial) { if !$0 && !snapshotMode { tutorialSeen = true } }
        .onReceive(NotificationCenter.default.publisher(for: .showTutorial)) { _ in withAnimation(.easeOut(duration: 0.25)) { showTutorial = true } }
        .onChange(of: draft) { if !snapshotMode { Store.draft = $0 } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    // MARK: effect list

    private var effectList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Effects").font(.headline)
                Button { withAnimation(.easeOut(duration: 0.25)) { showTutorial = true } } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless).help("Show the tutorial")
                Spacer()
                Button("ALL") { draft.effects = Catalog.allIDs }.buttonStyle(PixelButtonStyle())
                Button("NONE") { draft.effects = [] }.buttonStyle(PixelButtonStyle())
            }
            .padding([.horizontal, .top], 12).padding(.bottom, 8)
            List(Catalog.effects) { effect in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: selected(effect.id)).labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(effect.title).fontWeight(focused == effect.id ? .semibold : .regular)
                        Text(effect.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    if focused == effect.id { Image(systemName: "play.fill").foregroundStyle(.tint) }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { focused = focused == effect.id ? nil : effect.id }
            }
            Text("\(draft.effects.count) of \(Catalog.effects.count) selected · click a name to preview it")
                .font(.caption).foregroundStyle(.secondary).padding(12)
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
        VStack(alignment: .leading, spacing: 14) {
            PreviewView(effects: previewEffects, logo: draft.logo, showClock: draft.showClock)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
            Text(focused.map { id in "Previewing \(Catalog.effects.first { $0.id == id }!.title) — click it again to preview your selection" }
                 ?? (draft.effects.count == 1 ? "Previewing your selection" : "Previewing your selection in random order"))
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Text("Logo").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                PixelSegmented(selection: $draft.logo, options: [
                    ("apple-small", EffectConfig.logoTitle("apple-small")),
                    ("apple", EffectConfig.logoTitle("apple")),
                ])
                .frame(width: 300)
                Toggle("Show clock on the screensaver", isOn: $draft.showClock)
            }

            HStack(spacing: 12) {
                BigActionButton(title: "Use as Screensaver", subtitle: "Plays when your Mac is idle",
                                icon: .moon) { applyScreensaver() }
                BigActionButton(title: "Use as Wallpaper", subtitle: "Lives on your desktop",
                                icon: .storm) { applyWallpaper() }
            }
            .padding(.top, 4)
            .disabled(draft.effects.isEmpty)
            if draft.effects.isEmpty { Text("Select at least one effect.").font(.caption).foregroundStyle(.secondary) }

            if Bundle.main.bundlePath.contains("/AppTranslocation/") {
                Label("Move Applarchy to your Applications folder and open it from there, so it can start at login.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            Divider()
            statusRow(title: "Screensaver",
                      value: screensaver?.summary ?? (screensaverInstalled ? "Installed, all effects" : "Not installed")) {
                Button("Screen Saver Settings…") { Screensaver.openSettings() }.buttonStyle(PixelButtonStyle())
            }
            statusRow(title: "Wallpaper",
                      value: wallpaper.config.map { $0.summary + (wallpaper.paused ? " (paused)" : "") } ?? "Off") {
                if wallpaper.isRunning {
                    Button(wallpaper.paused ? "Resume" : "Pause") { wallpaper.paused.toggle() }.buttonStyle(PixelButtonStyle())
                    Button("Turn Off") { wallpaper.stop() }.buttonStyle(PixelButtonStyle())
                }
            }
        }
    }

    private func statusRow<Buttons: View>(title: String, value: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack {
            Text(title).fontWeight(.semibold).frame(width: 90, alignment: .leading)
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
    let logo: String
    let showClock: Bool

    func makeNSView(context: Context) -> StudioEffectView {
        let view = StudioEffectView(frame: NSRect(x: 0, y: 0, width: 560, height: 350), isPreview: true)!
        configure(view)
        view.startAnimation()
        return view
    }

    func updateNSView(_ view: StudioEffectView, context: Context) {
        guard view.effectCommands != effects || view.logoName != logo || view.showsClock != showClock else { return }
        view.stopAnimation()
        configure(view)
        view.startAnimation()
    }

    static func dismantleNSView(_ view: StudioEffectView, coordinator: ()) { view.stopAnimation() }

    private func configure(_ view: StudioEffectView) {
        view.effectCommands = effects
        view.logoName = logo
        view.showsClock = showClock
        view.logoRegionTop = showClock ? 171.0 / 982.0 : 0
        view.holdSeconds = 1.5
        view.followsScreensaverStop = false
        // Offscreen image at Retina scale: far cheaper than redrawing the window. (Window
        // snapshots draw the view directly, since they can't capture layer contents.)
        view.bitmapScale = ProcessInfo.processInfo.environment["OMARCHY_PREVIEW_DIRECT"] == nil ? 2 : nil
        view.animationTimeInterval = 1.0 / 30.0
    }
}
