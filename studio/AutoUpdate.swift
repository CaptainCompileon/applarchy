import AppKit
import Combine
import os.log

/// Updates that install themselves, for those who turn that on (asked once, and a tick in
/// the update prompt; Update there does it once). A new release's disk image is downloaded
/// in the background, checked, and its app kept ready ("staged") in Application Support.
/// Nothing is replaced while Applarchy runs: the staged app takes the installed one's place
/// the next time Applarchy starts, or on Restart Now.
///
/// What's checked before an app is staged, and again before it's installed: the disk image
/// is this repository's release file on github.com (HTTPS) and matches the SHA-256 GitHub
/// publishes for it; the app inside is this app (same bundle ID) at the announced version,
/// newer than the installed one, with its code signature intact. Applarchy isn't signed
/// with a Developer ID, so that signature names no publisher: the trust is GitHub's, as for
/// a download by hand.
final class AutoUpdate: ObservableObject {
    static let shared = AutoUpdate()

    enum Stage: Equatable {
        case idle
        case downloading(version: String, fraction: Double)
        /// Staged: it takes over at the next start.
        case ready(version: String)
        case failed(version: String, reason: String)
    }

    private enum Keys {
        static let enabled = "autoUpdate"
        static let asked = "autoUpdateAsked"
        /// A version macOS wouldn't let this app install: offered as a download instead.
        static let blocked = "autoUpdateBlocked"
        /// Set across the restart that installed an update: the version it replaced.
        static let updatedFrom = "autoUpdatedFrom"
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ reason: String) { errorDescription = reason }
    }

    @Published private(set) var stage = Stage.idle
    /// Download new releases in the background and install them at the next start.
    @Published var enabled = UserDefaults.standard.bool(forKey: Keys.enabled) {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled {
                if let release = Updates.shared.available { update(to: release, byUser: false) }
            } else {
                discard()             // off means off: what was downloaded isn't installed either
            }
        }
    }

    /// Whether the one-time question has been answered (in its own card, or by using the
    /// update prompt, which carries the same tick).
    var asked: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.asked) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.asked) }
    }

    /// Offered at all: the update check runs (not a dev build) and the app can be replaced.
    var isOffered: Bool { Updates.shared.isActive && Self.canInstall }
    var shouldAsk: Bool { isOffered && !asked && !enabled }

    /// `release` is being taken care of without a prompt: automatic updates are on, it can
    /// be installed here, and nothing has gone wrong with it.
    func handlesQuietly(_ release: Updates.Release) -> Bool {
        guard enabled, isOffered, release.asset != nil else { return false }
        if case .failed = stage { return false }
        return true
    }

    /// Update (rather than a download by hand) is on offer for `release`.
    func canInstall(_ release: Updates.Release) -> Bool { Self.canInstall && release.asset != nil }

    private static let log = OSLog(subsystem: "com.applarchy.app", category: "update")
    private var watcher: AnyCancellable?
    private var task: URLSessionDownloadTask?
    private var progress: NSKeyValueObservation?

    /// Follow the update check: with automatic updates on, each newer release is staged.
    func start() {
        watcher = Updates.shared.$available.receive(on: RunLoop.main).sink { [weak self] release in
            guard let self, self.enabled, let release else { return }
            self.update(to: release, byUser: false)
        }
    }

    // MARK: where things are

    /// Application Support/<app name>/Update: the staged app and, while it's being installed,
    /// the one it replaces (gone once the new copy has started).
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.name, isDirectory: true).appendingPathComponent("Update", isDirectory: true)
    }
    private static var staged: URL { folder.appendingPathComponent(AppIdentity.name + ".app") }
    private static var previous: URL { folder.appendingPathComponent("Previous.app") }

    /// Whether this copy can be replaced where it is: not one macOS runs from a hidden,
    /// read-only place (opened straight from Downloads) or from the disk image, and in a
    /// folder this user can change.
    static var canInstall: Bool {
        let bundle = Bundle.main.bundleURL, fm = FileManager.default
        return bundle.pathExtension == "app" && !bundle.path.contains("/AppTranslocation/")
            && fm.isWritableFile(atPath: bundle.path) && fm.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    // MARK: downloading and staging

    /// Download `release` and stage it. `byUser`: Update was clicked, so say why if it can't
    /// be done (and a version macOS refused before is tried again); otherwise stay quiet.
    func update(to release: Updates.Release, byUser: Bool) {
        switch stage {
        case .downloading: return
        case .ready(release.version): return
        default: break
        }
        guard Self.canInstall, let asset = release.asset else {
            if byUser { Updates.shared.download() }           // the release page: by hand
            return
        }
        if UserDefaults.standard.string(forKey: Keys.blocked) == release.version {
            guard byUser else {
                stage = .failed(version: release.version, reason: "macOS didn't let \(AppIdentity.name) replace itself")
                return
            }
            UserDefaults.standard.removeObject(forKey: Keys.blocked)
        }
        stage = .downloading(version: release.version, fraction: 0)
        let version = release.version
        os_log("downloading %{public}@%{public}@", log: Self.log, type: .default, version, byUser ? "" : " (automatic)")
        let finish: (Swift.Result<Void, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self, case .downloading(version, _) = self.stage else { return }     // turned off meanwhile
                self.task = nil
                self.progress = nil
                switch result {
                case .success:
                    os_log("%{public}@ is staged: it takes over at the next start", log: Self.log, type: .default, version)
                    self.stage = .ready(version: version)
                case .failure(let error):
                    os_log("couldn't stage %{public}@: %{public}@", log: Self.log, type: .default, version, error.localizedDescription)
                    self.stage = .failed(version: version, reason: error.localizedDescription)
                }
            }
        }
        // Testing, dev builds only: a local disk image in place of the release's (no checksum).
        if AppIdentity.isDev, let local = ProcessInfo.processInfo.environment["APPLARCHY_UPDATE_DMG"] {
            DispatchQueue.global(qos: .utility).async {
                finish(Swift.Result { try Self.stageApp(in: URL(fileURLWithPath: local), version: nil, asset: nil) })
            }
            return
        }
        let task = URLSession.shared.downloadTask(with: asset.url) { file, response, error in
            finish(Swift.Result {
                guard let file, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw Failure(error?.localizedDescription ?? "the download failed")
                }
                try Self.stageApp(in: file, version: version, asset: asset)      // here: `file` goes when this returns
            })
        }
        progress = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async {
                guard let self, case .downloading(version, _) = self.stage else { return }
                self.stage = .downloading(version: version, fraction: fraction)
            }
        }
        self.task = task
        task.resume()
    }

    /// Check the disk image at `dmg` and keep the app inside it ready. `asset`: what the
    /// download must match; `version`: what the app must be (nil: only newer than this one).
    private static func stageApp(in dmg: URL, version: String?, asset: Updates.Asset?) throws {
        let fm = FileManager.default
        if let asset {
            let data = try Data(contentsOf: dmg, options: .mappedIfSafe)
            guard data.count == asset.size, Updates.sha256(data) == asset.sha256 else {
                throw Failure("the download doesn't match the release's checksum")
            }
        }
        try? fm.removeItem(at: folder)
        let mount = folder.appendingPathComponent("mount", isDirectory: true)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        let image = folder.appendingPathComponent("update.dmg")       // a name hdiutil knows, and ours to keep while it's open
        try fm.copyItem(at: dmg, to: image)
        defer { try? fm.removeItem(at: image) }
        guard Screensaver.run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) == 0 else {
            throw Failure("the disk image couldn't be opened")
        }
        defer {
            Screensaver.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? fm.removeItem(at: mount)
        }
        let source = mount.appendingPathComponent(AppIdentity.name + ".app")
        try verify(source, version: version)
        guard Screensaver.run("/usr/bin/ditto", [source.path, staged.path]) == 0 else {
            try? fm.removeItem(at: staged)
            throw Failure("the new version couldn't be copied")
        }
        Screensaver.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        do { try verify(staged, version: version) } catch { try? fm.removeItem(at: staged); throw error }
    }

    /// `app` is this app, newer than the one running (at `version`, if given), and its code
    /// signature is intact: nothing in it changed since it was built. Its version.
    @discardableResult
    private static func verify(_ app: URL, version: String?) throws -> String {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == AppIdentity.id,
              let found = info["CFBundleShortVersionString"] as? String else {
            throw Failure("the download isn't \(AppIdentity.name)")
        }
        if let version, found != version { throw Failure("the download is version \(found), not \(version)") }
        guard Updates.isNewer(found, than: Updates.installed) else { throw Failure("the download isn't newer than this version") }
        guard Screensaver.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            throw Failure("the download is damaged")
        }
        return found
    }

    /// Forget a download in progress or a staged update.
    private func discard() {
        task?.cancel()
        task = nil
        progress = nil
        stage = .idle
        try? FileManager.default.removeItem(at: Self.folder)
    }

    // MARK: installing

    /// At launch, before anything else runs: install a staged update and start it instead
    /// of this copy. Returns if there's none, or it couldn't be installed (this copy carries on).
    static func installStagedAtLaunch() {
        let fm = FileManager.default
        try? fm.removeItem(at: previous)                          // the version replaced last time
        guard fm.fileExists(atPath: staged.path) else { return }
        if canInstall, install() { exit(0) }
        try? fm.removeItem(at: folder)                            // stale, damaged or refused: not tried again
    }

    /// Restart Now: install the staged update and start it. Returns only if that failed.
    func restartToUpdate() {
        guard case .ready(let version) = stage else { return }
        UserDefaults.standard.synchronize()
        if Self.install() { exit(0) }
        try? FileManager.default.removeItem(at: Self.folder)
        stage = .failed(version: version, reason: "macOS didn't let \(AppIdentity.name) replace itself")
    }

    /// Put the staged app in this one's place and open it; the caller then quits. This copy
    /// is moved aside first and moved back if anything fails, so there's always an app there.
    /// macOS may refuse (it guards apps against changes by others): that version is then
    /// remembered and offered as a download by hand.
    private static func install() -> Bool {
        let fm = FileManager.default, bundle = Bundle.main.bundleURL
        let version: String
        do { version = try verify(staged, version: nil) } catch {
            os_log("the staged update isn't installed: %{public}@", log: log, type: .default, error.localizedDescription)
            return false
        }
        do {
            try fm.moveItem(at: bundle, to: previous)
        } catch {
            os_log("couldn't move this copy aside: %{public}@", log: log, type: .default, error.localizedDescription)
            UserDefaults.standard.set(version, forKey: Keys.blocked)
            return false
        }
        do {
            try fm.moveItem(at: staged, to: bundle)
        } catch {
            os_log("couldn't put %{public}@ in place: %{public}@", log: log, type: .default, version, error.localizedDescription)
            try? fm.moveItem(at: previous, to: bundle)
            UserDefaults.standard.set(version, forKey: Keys.blocked)
            return false
        }
        // The new copy waits for this one to quit (--updated-from), then is the one instance.
        var arguments = ["-n", bundle.path, "--args", "--updated-from", "\(getpid())"]
        if CommandLine.arguments.contains("--background") { arguments.append("--background") }
        guard Screensaver.run("/usr/bin/open", arguments) == 0 else {
            os_log("%{public}@ wouldn't start: back to this copy", log: log, type: .default, version)
            try? fm.removeItem(at: bundle)                        // it wouldn't start: this copy back
            try? fm.moveItem(at: previous, to: bundle)
            UserDefaults.standard.set(version, forKey: Keys.blocked)
            return false
        }
        os_log("installed %{public}@ in place of %{public}@ and started it", log: log, type: .default, version, Updates.installed)
        UserDefaults.standard.set(Updates.installed, forKey: Keys.updatedFrom)
        UserDefaults.standard.synchronize()
        return true
    }

    /// The copy an update started waits for the one it replaced to quit, so the
    /// one-instance check doesn't take it for a second launch.
    static func waitForPredecessor() {
        guard let i = CommandLine.arguments.firstIndex(of: "--updated-from"), i + 1 < CommandLine.arguments.count,
              let pid = pid_t(CommandLine.arguments[i + 1]) else { return }
        for _ in 0..<100 where kill(pid, 0) == 0 { usleep(100_000) }
    }

    /// Once, in the copy an update started: "Updated from 2.8 to 2.9."
    static func takeUpdatedNote() -> String? {
        guard let from = UserDefaults.standard.string(forKey: Keys.updatedFrom) else { return nil }
        UserDefaults.standard.removeObject(forKey: Keys.updatedFrom)
        return Updates.isNewer(Updates.installed, than: from) ? "\(AppIdentity.name) was updated from \(from) to \(Updates.installed)." : nil
    }
}
