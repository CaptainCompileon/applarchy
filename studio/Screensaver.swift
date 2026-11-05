import AppKit

/// Installs and configures the "Applarchy" screensaver. Its settings live in
/// Resources/config.json inside the bundle, which the sandboxed screensaver can
/// always read. When the installed bundle's contents are writable by this user
/// (the case even for an all-users install made from System Settings), it is
/// updated in place and re-signed; otherwise System Settings' installer is used.
enum Screensaver {
    static let bundleName = AppIdentity.saverBundle

    static var template: URL { Bundle.main.resourceURL!.appendingPathComponent(bundleName) }

    static var installed: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent("Library/Screen Savers/\(bundleName)"),
                URL(fileURLWithPath: "/Library/Screen Savers/\(bundleName)")]
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var currentConfig: EffectConfig? {
        guard let url = installed?.appendingPathComponent("Contents/Resources/config.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(EffectConfig.self, from: data)
    }

    enum Outcome { case updated, installerOpened }

    static func apply(_ config: EffectConfig) throws -> Outcome {
        let json = try JSONEncoder().encode(config)
        // Any failure in place (e.g. macOS blocking changes to the bundle) falls back to the installer.
        if let installed, (try? updateInPlace(installed, json: json)) == true { return .updated }
        // Fresh copy with the config, handed to System Settings to install.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Applarchy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let copy = staging.appendingPathComponent(bundleName)
        try FileManager.default.copyItem(at: template, to: copy)
        try json.write(to: copy.appendingPathComponent("Contents/Resources/config.json"))
        clearQuarantine(copy)
        try sign(copy)
        NSWorkspace.shared.open(copy)
        return .installerOpened
    }

    /// Copy the template's files over the installed ones (same layout), add the
    /// config, re-sign, and restart the screensaver host so it loads the new code.
    private static func updateInPlace(_ bundle: URL, json: Data) throws -> Bool {
        let fm = FileManager.default
        let contents = bundle.appendingPathComponent("Contents")
        guard fm.isWritableFile(atPath: contents.path),
              fm.isWritableFile(atPath: contents.appendingPathComponent("Resources").path),
              fm.isWritableFile(atPath: contents.appendingPathComponent("MacOS").path) else { return false }
        let source = template.appendingPathComponent("Contents")
        guard let files = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        for case let file as URL in files {
            let relative = String(file.path.dropFirst(source.path.count + 1))
            if relative.hasPrefix("_CodeSignature") { continue }
            let target = contents.appendingPathComponent(relative)
            if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                try? fm.removeItem(at: target)
                try fm.copyItem(at: file, to: target)
            }
        }
        try json.write(to: contents.appendingPathComponent("Resources/config.json"))
        clearQuarantine(bundle)
        try sign(bundle)
        // A running legacyScreenSaver keeps the old code loaded.
        run("/usr/bin/pkill", ["-f", "legacyScreenSaver.appex"])
        return true
    }

    /// Switch the installed screensaver's smooth mode on or off, keeping its look.
    static func setSmooth(_ on: Bool) {
        guard var config = currentConfig, config.smoothTransition != on else { return }
        config.smoothTransition = on
        _ = try? apply(config)
    }

    /// A downloaded app carries the quarantine flag, and copies of its files inherit
    /// it; the screensaver host won't load a quarantined plug-in. The user already
    /// approved this app, so its own screensaver is cleared.
    private static func clearQuarantine(_ bundle: URL) {
        run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", bundle.path])
    }

    private static func sign(_ bundle: URL) throws {
        let status = run("/usr/bin/codesign", ["--force", "--sign", "-", bundle.path])
        if status != 0 { throw NSError(domain: "Applarchy", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "codesign failed (\(status))"]) }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!)
    }

    // MARK: choosing it

    /// macOS 14 and later keep the chosen screensaver in the wallpaper store's "Idle" slots
    /// (one per display and Space, all written when one is picked in System Settings);
    /// macOS 13 in this domain's moduleDict, which also holds "Start when inactive".
    private static let legacyDomain = "com.apple.screensaver" as CFString
    private static let provider = "com.apple.wallpaper.choice.screen-saver"

    /// Whether Applarchy is the screensaver macOS starts. nil when that can't be read.
    static var isSelected: Bool? {
        if let plist = LockScreen.loadStore() {
            let idle = LockScreen.slots(plist, "Idle")
            return !idle.isEmpty && idle.allSatisfy { chosenModule($0.slot)?.lastPathComponent == bundleName }
        }
        guard let module = legacyValue("moduleDict") as? [String: Any], let path = module["path"] as? String else { return nil }
        return (path as NSString).lastPathComponent == bundleName
    }

    /// "Start Screen Saver when inactive" is set to Never.
    static var neverStarts: Bool { (legacyValue("idleTime") as? Int) == 0 }

    /// Make the installed Applarchy the screensaver on every display and Space, after
    /// any lock screen change still being written, then call `done` on the main thread.
    static func select(then done: @escaping () -> Void = {}) {
        guard let installed, isSelected != true else { DispatchQueue.main.async(execute: done); return }
        LockScreen.storeQueue.async {
            if let plist = LockScreen.loadStore() {
                // A choice made before goes everywhere one could be.
                for key in ["SystemDefault", "AllSpacesAndDisplays"] {
                    if let entry = plist[key] as? NSMutableDictionary, entry["Idle"] == nil { entry["Idle"] = NSMutableDictionary() }
                }
                // As System Settings writes it: the bundle's file URL, without a trailing slash.
                let module = URL(fileURLWithPath: installed.path, isDirectory: false).absoluteString
                let configuration = try? PropertyListSerialization.data(fromPropertyList: ["module": ["relative": module]], format: .binary, options: 0)
                let options = try? PropertyListSerialization.data(fromPropertyList: ["values": [String: Any]()], format: .binary, options: 0)
                for (_, slot) in LockScreen.slots(plist, "Idle") {
                    slot["Content"] = NSMutableDictionary(dictionary: [
                        "Choices": [["Provider": provider, "Files": [], "Configuration": configuration ?? Data()]],
                        "Shuffle": "$null", "EncodedOptionValues": options ?? Data(),
                    ])
                    slot["LastSet"] = Date()
                }
                LockScreen.save(plist)
            } else {
                let module: [String: Any] = ["moduleName": (bundleName as NSString).deletingPathExtension, "path": installed.path, "type": 0]
                CFPreferencesSetValue("moduleDict" as CFString, module as CFDictionary, legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
                CFPreferencesSynchronize(legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
            }
            DispatchQueue.main.async(execute: done)
        }
    }

    private static var installWatch: Timer?

    /// After the installer was opened: once the copy with this config is in place (Install
    /// clicked), choose it. Gives up after ten minutes, e.g. when the install was cancelled.
    static func selectOnceInstalled(_ config: EffectConfig, then done: @escaping () -> Void) {
        installWatch?.invalidate()
        let deadline = Date().addingTimeInterval(600)
        installWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if currentConfig == config { timer.invalidate(); select(then: done) }
            else if Date() > deadline { timer.invalidate(); done() }
        }
    }

    /// The screensaver a store slot names, if it names one.
    private static func chosenModule(_ slot: NSDictionary) -> URL? {
        guard let choice = ((slot["Content"] as? NSDictionary)?["Choices"] as? [NSDictionary])?.first,
              choice["Provider"] as? String == provider,
              let data = choice["Configuration"] as? Data,
              let configuration = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? NSDictionary,
              let relative = (configuration["module"] as? NSDictionary)?["relative"] as? String else { return nil }
        return URL(string: relative)
    }

    /// System Settings writes these from another process, so read them fresh.
    private static func legacyValue(_ key: String) -> Any? {
        CFPreferencesSynchronize(legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return CFPreferencesCopyValue(key as CFString, legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}
