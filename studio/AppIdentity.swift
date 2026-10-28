import Foundation

/// Which Applarchy this is, from the Info.plist that scripts/flavor.sh writes: the
/// released "Applarchy" or a local "Applarchy DEV" build, which has its own app ID
/// (so its own settings and single-instance check), login item and screensaver,
/// and runs next to the released one.
enum AppIdentity {
    static let id = Bundle.main.bundleIdentifier ?? "com.applarchy.app"
    static let name = info("CFBundleName") ?? "Applarchy"
    static let isDev = info("ApplarchyFlavor") == "dev"
    /// The bundled screensaver's file name, also its name once installed.
    static let saverBundle = info("ApplarchySaverBundle") ?? "Applarchy.saver"
    /// Window title: a dev build also shows the commit it was built from.
    static var title: String { isDev ? "\(name) · \(info("ApplarchyCommit") ?? "local")" : name }

    private static func info(_ key: String) -> String? { Bundle.main.object(forInfoDictionaryKey: key) as? String }
}
