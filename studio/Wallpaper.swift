import AppKit
import ScreenSaver

/// The live wallpaper: one borderless window per screen at desktop level
/// (behind the icons), on every Space, ignoring the mouse. Rendering pauses
/// while the desktop is covered, the displays sleep, the screensaver runs, the
/// session is inactive, or the user pauses it.
final class Wallpaper: NSObject, ObservableObject {
    static let shared = Wallpaper()

    @Published private(set) var config: EffectConfig?
    @Published var paused = false { didSet { updateAnimation() } }
    private var windows: [NSWindow] = []
    private var views: [StudioEffectView] = []
    private var systemPaused = false

    var isRunning: Bool { config != nil }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(rebuild), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(systemPause), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemResume), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemPause), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemResume), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(systemPause), name: .init("com.apple.screensaver.didstart"), object: nil)
        dnc.addObserver(self, selector: #selector(systemResume), name: .init("com.apple.screensaver.didstop"), object: nil)
    }

    func start(_ config: EffectConfig) {
        self.config = config
        Store.wallpaper = config
        LoginItem.set(enabled: true)
        rebuild()
    }

    func stop() {
        config = nil
        Store.wallpaper = nil
        LoginItem.set(enabled: false)
        rebuild()
    }

    /// Resume the saved wallpaper (at launch).
    func restore() {
        if let saved = Store.wallpaper { config = saved; rebuild() }
    }

    @objc private func rebuild() {
        views.forEach { $0.stopAnimation() }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        views = []
        guard let config else { return }
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.setFrame(screen.frame, display: false)

            guard let view = StudioEffectView(frame: NSRect(origin: .zero, size: screen.frame.size), isPreview: false) else { continue }
            view.effectCommands = config.commands(forWallpaper: true)
            view.logoName = config.logo
            view.showsClock = false
            view.logoRegionTop = 0
            view.holdSeconds = 4
            view.maxEngineFrames = 200_000
            view.followsScreensaverStop = false
            view.bitmapScale = 1                    // 1x pixels, scaled up crisply: pixel art, cheap
            view.animationTimeInterval = 1.0 / 30.0
            window.contentView = view
            window.orderFrontRegardless()
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            windows.append(window)
            views.append(view)
        }
        updateAnimation()
    }

    @objc private func occlusionChanged() { updateAnimation() }
    @objc private func systemPause() { systemPaused = true; updateAnimation() }
    @objc private func systemResume() { systemPaused = false; updateAnimation() }

    private func updateAnimation() {
        for (window, view) in zip(windows, views) {
            let run = !paused && !systemPaused && window.occlusionState.contains(.visible)
            if run && !view.isAnimating { view.startAnimation() }
            if !run && view.isAnimating { view.stopAnimation() }
        }
    }
}

/// Start at login (in the background) while a wallpaper is set, via a LaunchAgent.
enum LoginItem {
    static let label = "com.applarchy.app"
    static var plist: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist") }

    static func set(enabled: Bool) {
        if !enabled { try? FileManager.default.removeItem(at: plist); return }
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Bundle.main.executablePath!, "--background"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
        ]
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (dict as NSDictionary).write(to: plist, atomically: true)
    }
}
