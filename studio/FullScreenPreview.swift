import AppKit

/// Click the window's preview: the selection plays full screen on every display, as
/// the screensaver would (clock and all), until a key, a click or the mouse moves.
/// Nothing is installed or applied: it shows what's picked, not what's saved.
final class FullScreenPreview {
    static let shared = FullScreenPreview()

    private var windows: [NSWindow] = []
    private var views: [StudioEffectView] = []
    private var monitor: Any?
    private var resignObserver: Any?
    private var shownAt = Date.distantPast
    /// The click that opened it, and a hand still settling on the mouse, don't close it.
    private static let grace = 1.0

    func show(_ config: EffectConfig) {
        guard windows.isEmpty, !config.effects.isEmpty else { return }
        shownAt = Date()
        for screen in NSScreen.screens {
            let window = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.setFrame(screen.frame, display: false)

            guard let view = StudioEffectView(frame: NSRect(origin: .zero, size: screen.frame.size), isPreview: false) else { continue }
            view.effectCommands = config.effects
            view.customLogoText = config.customLogo
            view.logoName = config.logo
            view.themeID = config.theme
            view.customTheme = config.customTheme
            view.showsClock = config.showClock
            view.clockStyle = config.clockStyle
            view.followsScreensaverStop = false        // a real screensaver starting or stopping isn't ours
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)
        }
        windows.first?.makeKey()
        views.forEach { $0.startAnimation() }           // after every window is up: they start together
        NSCursor.hide()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                                              .mouseMoved, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            if event.type == .mouseMoved || event.type == .scrollWheel,
               Date().timeIntervalSince(self.shownAt) < Self.grace { return nil }
            self.dismiss()
            return nil                                   // the key or click only closes it
        }
        // Switching apps (⌘Tab, a notification) closes it too.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil,
                                                                queue: .main) { [weak self] _ in self?.dismiss() }
    }

    func dismiss() {
        guard !windows.isEmpty else { return }
        views.forEach { $0.stopAnimation() }
        windows.forEach { $0.orderOut(nil) }
        views = []
        windows = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        NSCursor.unhide()
    }

    /// Borderless windows can't take keys by default; this one needs Escape and friends.
    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }
}
