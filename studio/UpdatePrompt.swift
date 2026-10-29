import SwiftUI

/// Over the window on every start while a newer release is out: the version, what's new
/// since the installed one (collapsed), Download… or Later. After Later, the status area's
/// Update row keeps it until the next start.
struct UpdatePrompt: View {
    let release: Updates.Release
    let installed: String
    let download: () -> Void
    let later: () -> Void
    @State private var showChanges = ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_CHANGES"] != nil   // env: screenshots only

    private var count: Int { release.changes.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("APPLARCHY \(release.version) IS AVAILABLE").font(Pixel.display).foregroundStyle(Color.ink)
                Text("You have \(installed).").foregroundStyle(.secondary)
                if count > 0 {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { showChanges.toggle() }
                    } label: {
                        Text("\(showChanges ? "▾" : "▸") WHAT'S NEW (\(count) \(count == 1 ? "CHANGE" : "CHANGES"))")
                            .foregroundStyle(Color.ink)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showChanges { changes }
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("Later", action: later).buttonStyle(PixelButtonStyle())
                    Button("Download…", action: download).buttonStyle(PixelButtonStyle(prominent: true))
                }
            }
            .padding(24)
            .frame(width: 540)
            .background(Color.surface(0.09))
            .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.85), lineWidth: 2))
            .background(Rectangle().fill(Color.ink.opacity(0.22)).offset(x: 6, y: 6))   // hard pixel shadow
            .compositingGroup()                    // one soft shadow for the card, not one per element inside it
            .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
        }
    }

    /// Every release since the installed one, newest first, with its changes.
    private var changes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(release.changes, id: \.version) { version in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(version.version).foregroundStyle(Color.ink)
                        ForEach(Array(version.items.enumerated()), id: \.offset) { _, item in
                            Text("• " + item).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxHeight: 240)
        .background(Color.surface(0.05))
        .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.2), lineWidth: 1.5))
    }
}
