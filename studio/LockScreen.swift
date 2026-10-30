import AppKit

/// Smooth mode's lock screen. Apps can't draw there; it shows the wallpaper macOS
/// has for the display. NSWorkspace only sets the current Space's picture, so after
/// setting it Applarchy copies that exact entry (as macOS wrote it) into the
/// display-wide and system-default slots and every Space of the wallpaper store,
/// then restarts WallpaperAgent to load it. The store is backed up first and put
/// back by restore(), which also brings back aerial and dynamic wallpapers.
enum LockScreen {
    /// Application Support/Applarchy (or "Applarchy DEV"): each build keeps its own
    /// backup and stills, so a DEV build can't restore or reset the released one's.
    private static var folder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private static var store: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }
    private static var backup: URL { folder.appendingPathComponent("wallpaper-store-backup.plist") }

    static func apply(_ config: EffectConfig) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: store, to: backup) }

        var files: [String: String] = [:]          // display UUID → still's file name
        let stamp = Int(Date().timeIntervalSince1970)
        for screen in NSScreen.screens {
            guard let uuid = displayUUID(screen),
                  let image = still(config, size: screen.frame.size, scale: screen.backingScaleFactor) else { continue }
            // A new file name each time, or macOS keeps showing its cached copy.
            let url = folder.appendingPathComponent("lock-\(uuid.prefix(8))-\(stamp).png")
            guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                  (try? data.write(to: url)) != nil else { continue }
            let bg = Themes.named(config.theme, custom: config.customTheme).background
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
                .fillColor: NSColor(red: CGFloat(bg >> 16 & 0xFF) / 255, green: CGFloat(bg >> 8 & 0xFF) / 255, blue: CGFloat(bg & 0xFF) / 255, alpha: 1),
            ])
            files[uuid] = url.lastPathComponent
        }
        // WallpaperAgent records the new picture in its store asynchronously.
        DispatchQueue.global().async {
            for _ in 0..<40 {
                if let s = try? Data(contentsOf: store), files.values.allSatisfy({ s.range(of: Data($0.utf8)) != nil }) { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            spreadToAllSpacesAndLockScreen(files)
            cleanUp(keeping: Set(files.values))
        }
    }

    static func restore() {
        guard FileManager.default.fileExists(atPath: backup.path) else { resetApplarchyEntries(); return }
        _ = try? FileManager.default.replaceItemAt(store, withItemAt: backup)
        resetApplarchyEntries()          // e.g. a backup taken after an earlier, partial takeover
    }

    /// No Space or display shows this build's still any more: another Applarchy (DEV or
    /// released) has applied its own Smooth Mode since, or a picture was chosen in System
    /// Settings. nil when the store can't be read.
    static var isTakenOver: Bool? {
        guard let plist = loadStore() else { return nil }
        return !desktopSlots(plist).contains { references($0.slot, stillMarker) }
    }

    /// How the store spells this build's stills: its URLs are percent-encoded ("Applarchy%20DEV").
    private static var stillMarker: String {
        "/\(AppIdentity.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? AppIdentity.name)/lock-"
    }

    // MARK: wallpaper store

    private static func loadStore() -> NSMutableDictionary? {
        guard let data = try? Data(contentsOf: store) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: nil)) as? NSMutableDictionary
    }

    private static func save(_ plist: NSMutableDictionary) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { return }
        try? data.write(to: store, options: .atomic)
        Screensaver.run("/usr/bin/killall", ["WallpaperAgent"])   // relaunches and reads the store
    }

    /// Every "Desktop" content dictionary in the store, with the display it belongs to (nil: all).
    private static func desktopSlots(_ plist: NSMutableDictionary) -> [(display: String?, slot: NSMutableDictionary)] {
        var out: [(String?, NSMutableDictionary)] = []
        func add(_ entry: Any?, _ display: String?) {
            if let d = (entry as? NSMutableDictionary)?["Desktop"] as? NSMutableDictionary { out.append((display, d)) }
        }
        add(plist["SystemDefault"], nil)
        add(plist["AllSpacesAndDisplays"], nil)
        for (uuid, entry) in (plist["Displays"] as? NSDictionary ?? [:]) { add(entry, uuid as? String) }
        for (_, space) in (plist["Spaces"] as? NSDictionary ?? [:]) {
            let space = space as? NSDictionary
            add(space?["Default"], nil)
            for (uuid, entry) in (space?["Displays"] as? NSDictionary ?? [:]) { add(entry, uuid as? String) }
        }
        return out
    }

    private static func references(_ slot: NSDictionary, _ needle: String) -> Bool {
        guard let content = slot["Content"] as? NSDictionary,
              let data = try? PropertyListSerialization.data(fromPropertyList: content, format: .binary, options: 0) else { return false }
        return data.range(of: Data(needle.utf8)) != nil
    }

    private static func spreadToAllSpacesAndLockScreen(_ files: [String: String]) {
        guard let plist = loadStore() else { return }
        let slots = desktopSlots(plist)
        // The entries macOS wrote for our stills, per display.
        var contents: [String: Any] = [:]
        for (uuid, file) in files {
            if let s = slots.first(where: { references($0.slot, file) }) { contents[uuid] = s.slot["Content"] }
        }
        guard let main = NSScreen.main.flatMap(displayUUID).flatMap({ contents[$0] }) ?? contents.values.first else { return }
        for (display, slot) in slots {
            slot["Content"] = (display.flatMap { contents[$0] } ?? main) as AnyObject
            slot["LastSet"] = Date()
        }
        save(plist)
    }

    /// Any slot still showing an Applarchy still goes back to macOS's default wallpaper.
    private static func resetApplarchyEntries() {
        guard let plist = loadStore() else { return }
        var changed = false
        for (_, slot) in desktopSlots(plist) where references(slot, stillMarker) {
            slot["Content"] = NSMutableDictionary(dictionary: [
                "Choices": [["Provider": "default", "Files": [], "Configuration": Data()]],
                "Shuffle": "$null", "EncodedOptionValues": "$null",
            ])
            changed = true
        }
        if changed { save(plist) } else { Screensaver.run("/usr/bin/killall", ["WallpaperAgent"]) }
    }

    private static func displayUUID(_ screen: NSScreen) -> String? {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    // MARK: the still

    /// The final logo as the wallpaper's hold mode draws it, rendered offscreen.
    static func still(_ config: EffectConfig, size: CGSize, scale: CGFloat) -> CGImage? {
        guard let view = StudioEffectView(frame: NSRect(origin: .zero, size: size), isPreview: true) else { return nil }
        view.customLogoText = config.customLogo
        view.logoName = config.logo
        view.themeID = config.theme
        view.customTheme = config.customTheme
        view.showsClock = config.showClock
        view.clockStyle = config.clockStyle
        view.clockVisible = false            // macOS draws its own clock on the lock screen
        view.holdsWhenDone = true
        view.followsScreensaverStop = false
        view.bitmapScale = scale
        view.startAnimation()
        view.stopAnimation()
        return view.snapshotImage()
    }

    private static func cleanUp(keeping keep: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix("lock-") && !keep.contains(f.lastPathComponent) {
            try? FileManager.default.removeItem(at: f)
        }
    }
}
