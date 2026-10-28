import AppKit
import IOKit.ps
import ScreenSaver
import os.log

/// The live wallpaper: one borderless window per screen at desktop level
/// (behind the icons), on every Space, ignoring the mouse. Rendering pauses
/// while the desktop is covered, the displays sleep, the screensaver runs, the
/// session is inactive, the user pauses it, or (optionally) on battery power or
/// in Low Power Mode.
final class Wallpaper: NSObject, ObservableObject {
    static let shared = Wallpaper()

    @Published private(set) var config: EffectConfig?
    @Published var paused = false { didSet { updateAnimation() } }
    @Published var options = Store.wallpaperOptions {
        didSet { Store.wallpaperOptions = options; if options.fps != oldValue.fps { rebuild() } else { updateAnimation() } }
    }
    /// Why the wallpaper is currently paused by a power setting, for the status line.
    @Published private(set) var powerPause: String?
    private var powerSource: CFRunLoopSource?
    /// The latest effect each screen's screensaver started, keyed by screen size ("WxH").
    private var handoffs: [String: StudioEffectView.Handoff] = [:]
    private var windows: [NSWindow] = []
    private var views: [StudioEffectView] = []
    private var systemPaused = false
    /// The screen is locked: the screensaver keeps running on the lock screen.
    private var locked = false
    private static let log = OSLog(subsystem: "com.applarchy.app", category: "wallpaper")

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
        dnc.addObserver(self, selector: #selector(screensaverWillStop), name: .init("com.apple.screensaver.willstop"), object: nil)
        // Power: battery/AC changes and Low Power Mode.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<Wallpaper>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        NotificationCenter.default.addObserver(self, selector: #selector(powerChanged), name: .NSProcessInfoPowerStateDidChange, object: nil)
        dnc.addObserver(self, selector: #selector(receivedHandoff(_:)), name: StudioEffectView.Handoff.notification, object: nil,
                        suspensionBehavior: .deliverImmediately)
        dnc.addObserver(self, selector: #selector(screenLocked), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(screenUnlocked), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    /// The screensaver's latest announcement for a screen size: from its pasteboard
    /// (always readable), or a notification that reached us, whichever is newer.
    private func latestHandoff(for size: CGSize) -> StudioEffectView.Handoff? {
        let board = StudioEffectView.Handoff.pasteboard(for: size).string(forType: .string).flatMap(StudioEffectView.Handoff.init(payload:))
        let note = handoffs[Self.key(size)]
        func stamp(_ h: StudioEffectView.Handoff) -> Date { max(h.startedAt, h.settleAt ?? .distantPast) }
        switch (board, note) {
        case let (b?, n?): return stamp(b) >= stamp(n) ? b : n
        case let (b, n): return b ?? n
        }
    }

    /// Smooth mode: locking the screen starts the screensaver straight away, so the
    /// lock screen plays the animation; unlocking hands it back to the desktop.
    @objc private func screenLocked() {
        locked = true
        guard config?.smoothTransition == true else { return }
        systemPause()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"),
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func screenUnlocked() {
        locked = false
        systemResume()
    }

    /// The screensaver is closing because the mouse moved. macOS doesn't reliably send
    /// didstop, so resume here too: a moment later, so the screensaver's "settling"
    /// announcement is in first. Not while locked: the screensaver then keeps running
    /// on the lock screen, and unlocking resumes.
    @objc private func screensaverWillStop() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [self] in
            guard !locked else { return }
            systemResume()
        }
    }

    @objc private func receivedHandoff(_ note: Notification) {
        guard let payload = note.object as? String, let h = StudioEffectView.Handoff(payload: payload) else { return }
        DispatchQueue.main.async { self.handoffs[Self.key(h.size)] = h }
    }

    private static func key(_ size: CGSize) -> String { "\(Int(size.width))x\(Int(size.height))" }

    @objc private func powerChanged() {
        DispatchQueue.main.async { self.updateAnimation() }
    }

    private var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    func start(_ config: EffectConfig) {
        // Effects announced under the previous look carry its theme in their commands.
        if config != self.config {
            handoffs.removeAll()
            for screen in NSScreen.screens { StudioEffectView.Handoff.pasteboard(for: screen.frame.size).clearContents() }
        }
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
        for window in windows {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
            window.orderOut(nil)
        }
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
            view.effectCommands = config.commands(forWallpaper: !config.smoothTransition)
            view.customLogoText = config.customLogo
            view.logoName = config.logo
            view.themeID = config.theme
            // Smooth transition: the screensaver's layout (so the logo doesn't move), minus the
            // clock itself, playing the handed-off effect to its end and holding it.
            view.showsClock = config.smoothTransition && config.showClock
            view.clockStyle = config.clockStyle
            view.clockVisible = false
            view.holdsWhenDone = config.smoothTransition
            view.handoff = latestHandoff(for: screen.frame.size)
            view.holdSeconds = 4
            view.maxEngineFrames = 200_000
            view.followsScreensaverStop = false
            view.bitmapScale = 1                    // 1x pixels, scaled up crisply: pixel art, cheap
            view.matchesDisplayRate = false         // the picker's rate, which may be Auto
            view.animationTimeInterval = 1.0 / Double(options.rate(displayHz: screen.maximumFramesPerSecond))
            window.contentView = view
            window.orderFrontRegardless()
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            windows.append(window)
            views.append(view)
        }
        updateAnimation()
    }

    @objc private func occlusionChanged() { updateAnimation() }
    @objc private func systemPause() {
        os_log("pause", log: Self.log, type: .default)
        systemPaused = true
        updateAnimation()
    }
    @objc private func systemResume() {
        guard systemPaused else { updateAnimation(); return }   // willstop, didstop and wake may all arrive
        os_log("resume%{public}@", log: Self.log, type: .default, config?.smoothTransition == true ? " (smooth: picking up the handoff)" : "")
        systemPaused = false
        if config?.smoothTransition == true {
            // Pick up the screensaver's latest effect on each screen, from where it is now.
            for (window, view) in zip(windows, views) {
                view.handoff = latestHandoff(for: window.frame.size) ?? view.handoff
                if view.isAnimating { view.stopAnimation() }
            }
        }
        updateAnimation()
    }

    private func updateAnimation() {
        if options.pauseOnBattery && onBattery { powerPause = "on battery" }
        else if options.pauseInLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled { powerPause = "Low Power Mode" }
        else { powerPause = nil }
        for (window, view) in zip(windows, views) {
            let visible = window.occlusionState.contains(.visible)
            let run = !paused && !systemPaused && powerPause == nil && visible
            os_log("%{public}dx%{public}d: %{public}@", log: Self.log, type: .default, Int(window.frame.width), Int(window.frame.height),
                   run ? "run" : "stop (\([paused ? "paused" : nil, systemPaused ? "screensaver/sleep" : nil, powerPause, visible ? nil : "covered"].compactMap { $0 }.joined(separator: ", ")))")
            if run && !view.isAnimating { view.startAnimation() }
            if !run && view.isAnimating { view.stopAnimation() }
        }
    }
}

/// Start at login (in the background) while a wallpaper is set, via a LaunchAgent.
enum LoginItem {
    static let label = AppIdentity.id
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
