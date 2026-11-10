import AppKit
import CryptoKit

/// Checks GitHub for a newer release: at launch, once a day, when the app becomes active
/// after a few hours, and on demand (Check for Updates…). One anonymous request to the
/// public releases API; nothing else is sent. What happens with a newer release is
/// AutoUpdate's: installed in the background for those who turned that on, else offered.
final class Updates: ObservableObject {
    static let shared = Updates()
    static let repo = "CaptainCompileon/applarchy"

    struct Release: Equatable {
        var version: String
        var url: URL
        /// What changed in each release newer than the installed one, newest first:
        /// the pull request titles from its notes.
        var changes: [(version: String, items: [String])]
        /// Its disk image, when it has one Applarchy may install by itself (see `asset`).
        var asset: Asset?

        static func == (a: Release, b: Release) -> Bool { a.version == b.version && a.url == b.url }
    }

    /// A release's disk image: where it is, how big, and the SHA-256 GitHub publishes for it.
    struct Asset: Equatable {
        var url: URL
        var size: Int
        var sha256: String
    }

    enum Result { case upToDate(String), available(Release), failed(String) }

    @Published private(set) var available: Release?
    /// Later was clicked: no prompt again until the app restarts (the status area keeps it).
    @Published private(set) var promptDismissed = false
    /// The check runs (start() was called): not in a dev build, which leaves updates alone.
    private(set) var isActive = false
    private var lastChecked: Date?
    private var timer: Timer?

    /// The installed version. APPLARCHY_PRETEND_VERSION overrides it, to try the notices.
    var current: String {
        ProcessInfo.processInfo.environment["APPLARCHY_PRETEND_VERSION"] ?? Self.installed
    }

    /// The version of the app that's running, whatever is pretended.
    static var installed: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    /// The window's update prompt, on every start until Later.
    var prompt: Release? { promptDismissed ? nil : available }

    func start() {
        isActive = true
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.check() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastChecked ?? .distantPast) > 3 * 3600 else { return }
            self.check()
        }
    }

    func dismiss() { promptDismissed = true }

    /// Show the prompt again (Check for Updates… found one).
    func showPrompt() { promptDismissed = false }

    /// Open the release page; the prompt has done its job.
    func download() {
        guard let url = available?.url else { return }
        NSWorkspace.shared.open(url)
        dismiss()
    }

    func check(_ done: ((Result) -> Void)? = nil) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases?per_page=30")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let result: Result
            if let data, let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                result = Self.release(in: list, newerThan: self.current).map(Result.available) ?? .upToDate(self.current)
            } else if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                result = .failed(status == 403 ? "GitHub is limiting requests, try again in a while" : "GitHub answered \(status)")
            } else {
                result = .failed(error?.localizedDescription ?? "no answer from GitHub")
            }
            DispatchQueue.main.async {
                switch result {
                case .available(let release): self.available = release; self.lastChecked = Date()
                case .upToDate: self.available = nil; self.lastChecked = Date()
                case .failed: break                       // keep what we knew
                }
                done?(result)
            }
        }.resume()
    }

    /// The newest published release newer than `installed` in GitHub's list of releases, with
    /// what changed in every release since `installed`. nil when there's none.
    static func release(in list: [[String: Any]], newerThan installed: String) -> Release? {
        let newer = list.compactMap { json -> (version: String, url: URL, body: String, asset: Asset?)? in
            guard json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            return isNewer(version, than: installed) ? (version, page, json["body"] as? String ?? "", asset(in: json)) : nil
        }.sorted { isNewer($0.version, than: $1.version) }
        guard let latest = newer.first else { return nil }
        return Release(version: latest.version, url: latest.url, changes: newer.map { ($0.version, items($0.body)) }, asset: latest.asset)
    }

    /// A release's disk image, if Applarchy may install it by itself: a .dmg among its files, at
    /// a trusted address, with the SHA-256 GitHub computed when it was uploaded. Without one,
    /// the release is only offered as a download.
    static func asset(in release: [String: Any]) -> Asset? {
        for file in release["assets"] as? [[String: Any]] ?? [] {
            guard let name = file["name"] as? String, name.hasSuffix(".dmg"),
                  let url = (file["browser_download_url"] as? String).flatMap(URL.init(string:)), isTrustedDownload(url),
                  let size = file["size"] as? Int, size > 0,
                  let digest = file["digest"] as? String, digest.hasPrefix("sha256:") else { continue }
            let sha256 = String(digest.dropFirst("sha256:".count)).lowercased()
            guard sha256.utf8.count == 64, sha256.allSatisfy(\.isHexDigit) else { continue }
            return Asset(url: url, size: size, sha256: sha256)
        }
        return nil
    }

    /// Only this repository's release files on github.com, over HTTPS.
    static func isTrustedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/\(repo)/releases/download/")
            && !url.pathComponents.contains("..")
    }

    /// SHA-256 of `data`, as lowercase hex.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// "* Title by @user in https://…/pull/12" (GitHub's generated notes) → "Title".
    static func items(_ body: String) -> [String] {
        body.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("* ") || s.hasPrefix("- ") else { return nil }
            s.removeFirst(2)
            if let by = s.range(of: " by @", options: .backwards) { s = String(s[..<by.lowerBound]) }
            return s.isEmpty ? nil : s
        }
    }

    /// "2.1" > "2.0.3", numerically per component.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
