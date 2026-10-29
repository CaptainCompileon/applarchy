import AppKit

/// Checks GitHub for a newer release: at launch, once a day, when the app becomes active
/// after a few hours, and on demand (Check for Updates…). One anonymous request to the
/// public releases API; nothing else is sent.
final class Updates: ObservableObject {
    static let shared = Updates()
    static let repo = "CaptainCompileon/applarchy"

    struct Release: Equatable {
        var version: String
        var url: URL
        /// What changed in each release newer than the installed one, newest first:
        /// the pull request titles from its notes.
        var changes: [(version: String, items: [String])]

        static func == (a: Release, b: Release) -> Bool { a.version == b.version && a.url == b.url }
    }

    enum Result { case upToDate(String), available(Release), failed(String) }

    @Published private(set) var available: Release?
    /// Later was clicked: no prompt again until the app restarts (the status area keeps it).
    @Published private(set) var promptDismissed = false
    private var lastChecked: Date?
    private var timer: Timer?

    /// The installed version. APPLARCHY_PRETEND_VERSION overrides it, to try the notices.
    var current: String {
        ProcessInfo.processInfo.environment["APPLARCHY_PRETEND_VERSION"]
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The window's update prompt, on every start until Later.
    var prompt: Release? { promptDismissed ? nil : available }

    func start() {
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
                // Published releases newer than the installed one, newest first.
                let newer = list.compactMap { json -> (version: String, url: URL, body: String)? in
                    guard json["draft"] as? Bool != true, json["prerelease"] as? Bool != true,
                          let tag = json["tag_name"] as? String,
                          let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
                    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                    return Self.isNewer(version, than: self.current) ? (version, page, json["body"] as? String ?? "") : nil
                }.sorted { Self.isNewer($0.version, than: $1.version) }
                if let latest = newer.first {
                    result = .available(Release(version: latest.version, url: latest.url,
                                                changes: newer.map { ($0.version, Self.items($0.body)) }))
                } else {
                    result = .upToDate(self.current)
                }
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
