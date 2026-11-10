import SwiftUI

/// Over the window on every start while a newer release is out: the version, what's new
/// since the installed one (collapsed), Update or Later. Update downloads it in the
/// background, to take over at the next start, and with the tick does the same for every
/// later release (AutoUpdate). Where this copy can't be replaced it's Download… instead: the
/// release's page. After Later, the status area's Update row keeps it until the next start.
struct UpdatePrompt: View {
    let release: Updates.Release
    let installed: String
    /// Update is possible here; otherwise only a download by hand.
    let canInstall: Bool
    /// Update (or Download…) was clicked, with the tick's state.
    let update: (_ automatic: Bool) -> Void
    let later: () -> Void
    @State private var automatic: Bool

    init(release: Updates.Release, installed: String, canInstall: Bool, automatic: Bool,
         update: @escaping (_ automatic: Bool) -> Void, later: @escaping () -> Void) {
        self.release = release
        self.installed = installed
        self.canInstall = canInstall
        self.update = update
        self.later = later
        _automatic = State(initialValue: automatic)
    }
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
                if canInstall {
                    Button { automatic.toggle() } label: {
                        HStack(alignment: .top, spacing: 8) {          // the box beside the first line, not the middle
                            PixelCheckbox(on: automatic)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Update automatically from now on").foregroundStyle(Color.ink)
                                Text("New versions download in the background and take over the next time Applarchy starts.")
                                    .foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                HStack(spacing: 10) {
                    Spacer()
                    Button("Later", action: later).buttonStyle(PixelButtonStyle())
                    Button(canInstall ? "Update" : "Download…") { update(automatic) }.buttonStyle(PixelButtonStyle(prominent: true))
                }
            }
            .pixelCard(width: 540)
        }
        .font(Pixel.body)
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

/// Asked once, over the window, when Applarchy opens: update automatically? Either answer
/// is kept; the Applarchy menu's Update Automatically changes it later.
struct AutoUpdateQuestion: View {
    /// Turn On (true) or Not Now (false).
    let answer: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture {}                       // swallow clicks behind the card
            VStack(alignment: .leading, spacing: 14) {
                Text("UPDATE AUTOMATICALLY?").font(Pixel.display).foregroundStyle(Color.ink)
                Text("Applarchy can download new versions in the background and switch to them the next time it starts. Nothing is replaced while it runs.")
                    .foregroundStyle(Color.ink.opacity(0.8)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                Text("It only asks GitHub, as it already does to tell you about updates. You can change this any time: Update Automatically, in the Applarchy menu.")
                    .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Spacer()
                    Button("Not Now") { answer(false) }.buttonStyle(PixelButtonStyle())
                    Button("Turn On") { answer(true) }.buttonStyle(PixelButtonStyle(prominent: true))
                }
            }
            .pixelCard(width: 540)
        }
        .font(Pixel.body)
    }
}

private extension View {
    /// A card over the dimmed window: padded, bordered, with the hard pixel shadow.
    func pixelCard(width: CGFloat) -> some View {
        padding(24)
            .frame(width: width)
            .background(Color.surface(0.09))
            .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.85), lineWidth: 2))
            .background(Rectangle().fill(Color.ink.opacity(0.22)).offset(x: 6, y: 6))   // hard pixel shadow
            .compositingGroup()                    // one soft shadow for the card, not one per element inside it
            .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
    }
}
