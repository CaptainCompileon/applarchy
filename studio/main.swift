import AppKit
import SwiftUI

/// Applarchy: pick Omarchy's ttfx effects and use them as the screensaver or as a
/// live wallpaper. Runs as a menu bar app while a wallpaper is set.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem!
    private let background = CommandLine.arguments.contains("--background")

    func applicationDidFinishLaunching(_ note: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--window-snapshot"), i + 1 < CommandLine.arguments.count {
            windowSnapshot(to: CommandLine.arguments[i + 1])
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            snapshot(to: CommandLine.arguments[i + 1])     // testing: render the window offscreen
            return
        }
        migrateEarlierVersions()
        Wallpaper.shared.restore()
        buildMainMenu()
        buildStatusItem()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showWindow), name: .init("com.applarchy.app.show"), object: nil)
        if !background { showWindow() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: window

    @objc func showWindow() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "Applarchy"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: ContentView().environmentObject(Wallpaper.shared))
            w.center()
            window = w
        }
        NSApp.setActivationPolicy(.regular)       // Dock icon and Cmd-Tab while the window is open
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ note: Notification) {
        window?.contentView = nil                  // stop the preview
        window = nil
        if Wallpaper.shared.isRunning {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.terminate(nil)                   // nothing left to run
        }
    }

    // MARK: menus

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Applarchy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = PixelIcon.storm.templateImage()
        statusItem.button?.image?.accessibilityDescription = "Applarchy"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Open Applarchy…", #selector(showWindow)))
        menu.addItem(item("Show Tutorial…", #selector(showTutorial)))
        menu.addItem(.separator())
        let wp = Wallpaper.shared
        if let config = wp.config {
            menu.addItem(withTitle: "Wallpaper: \(config.summary)", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(item(wp.paused ? "Resume Wallpaper" : "Pause Wallpaper", #selector(togglePause)))
            menu.addItem(item("Turn Off Wallpaper", #selector(stopWallpaper)))
        } else {
            menu.addItem(withTitle: "Wallpaper: Off", action: nil, keyEquivalent: "").isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit Applarchy", #selector(NSApplication.terminate(_:)), target: NSApp))
    }

    private func item(_ title: String, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = target ?? self
        return i
    }

    @objc private func showTutorial() {
        showWindow()
        DispatchQueue.main.async { NotificationCenter.default.post(name: .showTutorial, object: nil) }
    }

    @objc private func togglePause() { Wallpaper.shared.paused.toggle() }
    @objc private func stopWallpaper() {
        Wallpaper.shared.stop()
        if window == nil { NSApp.terminate(nil) }
    }

    /// Testing: render the main view and each tutorial step to PNGs (`<path>-main.png`, `<path>-step<N>.png`).
    /// ImageRenderer can't draw the embedded AppKit preview, which shows as a placeholder.
    @MainActor private func snapshot(to path: String) {
        DispatchQueue.main.async { @MainActor in
            @MainActor func save<V: View>(_ view: V, _ suffix: String, _ size: CGSize) {
                let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
                r.scale = 2
                guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
                try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(path)-\(suffix).png"))
            }
            UserDefaults.standard.set(true, forKey: "tutorialSeen")
            save(ContentView().environmentObject(Wallpaper.shared).background(Color(white: 0.16)), "main", CGSize(width: 1000, height: 680))
            for i in 0..<4 {
                save(TutorialOverlay(isPresented: .constant(true), page: i).background(Color(white: 0.16)), "step\(i)", CGSize(width: 1000, height: 680))
            }
            UserDefaults.standard.removeObject(forKey: "tutorialSeen")
            exit(0)
        }
    }

    /// Testing/README: a real window placed off-screen, captured after the preview has
    /// animated for a while. Selection from OMARCHY_SNAPSHOT ("effects;logo;clock;focus;tutorial").
    private func windowSnapshot(to path: String) {
        let spec = (ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT"] ?? "").split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        func field(_ i: Int) -> String { i < spec.count ? spec[i] : "" }
        let effects = field(0).isEmpty ? Catalog.allIDs : field(0).split(separator: ",").map(String.init)
        let draft = EffectConfig(effects: effects, logo: field(1).isEmpty ? "apple-small" : field(1), showClock: field(2) != "0")
        let content = ContentView(snapshot: (draft, field(3).isEmpty ? nil : field(3), field(4) == "1"))
            .environmentObject(Wallpaper.shared)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Applarchy"
        w.appearance = NSAppearance(named: .darkAqua)
        w.backgroundColor = NSColor(white: 0.13, alpha: 1)
        w.contentView = NSHostingView(rootView: content)
        w.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        w.orderFrontRegardless()
        let delay = Double(ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_DELAY"] ?? "") ?? 5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    // MARK: migration

    /// Take over from earlier builds: "Omarchy Studio" (same app, old name) and the
    /// standalone "Omarchy Wallpaper", keeping their settings.
    private func migrateEarlierVersions() {
        migrateOmarchyStudio()
        migrateOldWallpaperApp()
    }

    private func migrateOmarchyStudio() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let oldAgent = home.appendingPathComponent("Library/LaunchAgents/org.omarchy.studio.plist")
        let oldApp = home.appendingPathComponent("Applications/Omarchy Studio.app")
        guard FileManager.default.fileExists(atPath: oldAgent.path) || FileManager.default.fileExists(atPath: oldApp.path) else { return }
        Screensaver.run("/usr/bin/pkill", ["-x", "OmarchyStudio"])
        if let old = UserDefaults(suiteName: "org.omarchy.studio") {
            let new = UserDefaults.standard
            for key in ["draft", "wallpaper", "tutorialSeen"] where new.object(forKey: key) == nil {
                if let value = old.object(forKey: key) { new.set(value, forKey: key) }
            }
        }
        try? FileManager.default.removeItem(at: oldAgent)
        try? FileManager.default.removeItem(at: oldApp)
        if let wallpaper = Store.wallpaper { Wallpaper.shared.start(wallpaper) }   // re-creates the login item under the new name
    }

    private func migrateOldWallpaperApp() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let oldAgent = home.appendingPathComponent("Library/LaunchAgents/org.omarchy.wallpaper.plist")
        guard FileManager.default.fileExists(atPath: oldAgent.path) else { return }
        Screensaver.run("/bin/launchctl", ["bootout", "gui/\(getuid())/org.omarchy.wallpaper"])
        Screensaver.run("/usr/bin/pkill", ["-x", "OmarchyWallpaper"])
        try? FileManager.default.removeItem(at: oldAgent)
        try? FileManager.default.removeItem(at: home.appendingPathComponent("Applications/Omarchy Wallpaper.app"))
        if Store.wallpaper == nil {
            Wallpaper.shared.start(EffectConfig(effects: ["thunderstorm"], logo: "apple", showClock: false))
        }
    }
}

// One instance: a second launch asks the running one to show its window.
let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    .filter { $0.processIdentifier != getpid() }
if !others.isEmpty && !CommandLine.arguments.contains("--snapshot") && !CommandLine.arguments.contains("--window-snapshot") {
    if !CommandLine.arguments.contains("--background") {
        DistributedNotificationCenter.default().postNotificationName(.init("com.applarchy.app.show"), object: nil, userInfo: nil, deliverImmediately: true)
    }
    exit(0)
}

Pixel.register()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
