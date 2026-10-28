import AppKit

/// Installs and configures the "Applarchy" screensaver. Its settings live in
/// Resources/config.json inside the bundle, which the sandboxed screensaver can
/// always read. When the installed bundle's contents are writable by this user
/// (the case even for an all-users install made from System Settings), it is
/// updated in place and re-signed; otherwise System Settings' installer is used.
enum Screensaver {
    static let bundleName = "Applarchy.saver"
    static let executable = "ApplarchySaverView"

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
}
