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
        /// The first few changes from the release notes (pull request titles).
        var highlights: [String]
    }

    enum Result { case upToDate(String), available(Release), failed(String) }

    @Published private(set) var available: Release?
    /// The version whose notice was dismissed (Later or Download…): no banner for it again.
    @Published private(set) var dismissed = UserDefaults.standard.string(forKey: "updateDismissed")
    private var lastChecked: Date?
    private var timer: Timer?

    /// The installed version. APPLARCHY_PRETEND_VERSION overrides it, to try the notices.
    var current: String {
        ProcessInfo.processInfo.environment["APPLARCHY_PRETEND_VERSION"]
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The window's banner: an update that hasn't been dismissed.
    var banner: Release? { available.flatMap { $0.version == dismissed ? nil : $0 } }

    func start() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.check() }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastChecked ?? .distantPast) > 3 * 3600 else { return }
            self.check()
        }
    }

    func dismiss() {
        guard let version = available?.version else { return }
        dismissed = version
        UserDefaults.standard.set(version, forKey: "updateDismissed")
    }

    /// Open the release page; its notice has done its job.
    func download() {
        guard let url = available?.url else { return }
        NSWorkspace.shared.open(url)
        dismiss()
    }

    func check(_ done: ((Result) -> Void)? = nil) {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let result: Result
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String,
               let page = (json["html_url"] as? String).flatMap(URL.init(string:)) {
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let release = Release(version: latest, url: page, highlights: Self.highlights(json["body"] as? String ?? ""))
                result = Self.isNewer(latest, than: self.current) ? .available(release) : .upToDate(self.current)
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

    /// "* Title by @user in https://…/pull/12" (GitHub's generated notes) → "Title"; the first few.
    static func highlights(_ body: String) -> [String] {
        body.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("* ") || s.hasPrefix("- ") else { return nil }
            s.removeFirst(2)
            if let by = s.range(of: " by @", options: .backwards) { s = String(s[..<by.lowerBound]) }
            return s.isEmpty ? nil : s
        }.prefix(3).map { $0 }
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
