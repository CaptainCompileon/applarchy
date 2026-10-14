import SwiftUI

/// First-run walkthrough: a floating card over the dimmed window, four steps
/// with pictures (a live preview and real renders of the effects).
struct TutorialOverlay: View {
    @Binding var isPresented: Bool
    @State var page = Int(ProcessInfo.processInfo.environment["OMARCHY_SNAPSHOT_PAGE"] ?? "") ?? 0   // env: screenshots only
    @State private var forward = true

    private let steps: [Step] = [
        Step(title: "Welcome to Applarchy",
             body: "Omarchy's 37 terminal text effects, running natively on your Mac — over the Apple logo, in glorious pixel art.",
             picture: .live),
        Step(title: "Pick your effects",
             body: "Tick one, a few, or all of them. Your picks play in random order, each once before any repeat. Click an effect's name to preview just that one.",
             picture: .list),
        Step(title: "Choose your vibe",
             body: "Go Chill Guy with the small logo, or Apple Evangelist with the big one. The screensaver can also show a pixel clock.",
             picture: .pair(Shot(title: "Chill Guy", effects: ["highlight"], logo: "apple-small", clock: false),
                            Shot(title: "Apple Evangelist", effects: ["highlight"], logo: "apple", clock: false))),
        Step(title: "Screensaver or wallpaper",
             body: "Hit Use as Screensaver, or Use as Wallpaper to run it live behind your desktop icons. Pause or turn it off any time from the ⛈ icon in the menu bar.",
             picture: .pair(Shot(title: "Screensaver", effects: ["matrix", "decrypt"], logo: "apple-small", clock: true),
                            Shot(title: "Wallpaper", effects: ["thunderstorm"], logo: "apple", clock: false))),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture {}                       // swallow clicks behind the card
            card
                .frame(width: 600)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                StepPicture(picture: steps[page].picture)
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(height: 310)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding([.horizontal, .top], 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("STEP \(page + 1) OF \(steps.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(.secondary)
                Text(steps[page].title).font(.system(size: 22, weight: .bold))
                Text(steps[page].body).font(.system(size: 13.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 54, alignment: .top)
            }
            .id("text\(page)")
            .transition(.opacity)
            .padding(.horizontal, 24).padding(.top, 18)

            HStack {
                Button("Skip") { close() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .opacity(page == steps.count - 1 ? 0 : 1)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(steps.indices, id: \.self) { i in
                        Rectangle()
                            .fill(i == page ? AnyShapeStyle(Color.white) : AnyShapeStyle(.quaternary))
                            .frame(width: i == page ? 20 : 6, height: 6)
                            .onTapGesture { go(to: i) }
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    if page > 0 {
                        Button { go(to: page - 1) } label: {
                            Text("◀").font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color(white: 0.14))
                                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                        }
                        .buttonStyle(PixelPressStyle(shadow: 3, hovering: false))
                    }
                    Button { page == steps.count - 1 ? close() : go(to: page + 1) } label: {
                        Text((page == steps.count - 1 ? "Get Started" : "Next") + " ▶")
                            .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.white)
                    }
                    .buttonStyle(PixelPressStyle(shadow: 3, hovering: false))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
        }
    }

    private func go(to i: Int) {
        guard i != page, steps.indices.contains(i) else { return }
        forward = i > page
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { page = i }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { isPresented = false }
    }

    struct Step {
        let title: String
        let body: String
        let picture: Picture
    }

    enum Picture {
        case live
        case list
        case pair(Shot, Shot)
    }
}

private struct StepPicture: View {
    let picture: TutorialOverlay.Picture

    var body: some View {
        switch picture {
        case .live:
            PreviewView(effects: ["beams", "decrypt", "fireworks", "laseretch", "thunderstorm"], logo: "apple-small", showClock: false)
                .overlay(alignment: .bottomLeading) { Badge(text: "LIVE", icon: "dot.radiowaves.left.and.right").padding(12) }
        case .list:
            ListIllustration()
        case let .pair(left, right):
            HStack(spacing: 10) { left; right }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// A small live preview with a caption (the tutorial's pictures are rendered live,
/// so no logo artwork ships with the app).
struct Shot: View {
    let title: String
    let effects: [String]
    let logo: String
    let clock: Bool
    var body: some View {
        VStack(spacing: 10) {
            PreviewView(effects: effects, logo: logo, showClock: clock)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Badge: View {
    let text: String
    let icon: String
    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10.5, weight: .bold)).tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
    }
}

/// A mock of the effect list, with a small matrix render beside it.
private struct ListIllustration: View {
    private let rows: [(String, Bool, Bool)] = [
        ("Beams", true, false), ("Blackhole", false, false), ("Fireworks", true, false),
        ("Matrix", true, true), ("Thunderstorm", true, false), ("Waves", false, false),
    ]
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    let (name, on, playing) = rows[i]
                    HStack(spacing: 10) {
                        Image(systemName: on ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15))
                            .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(0.4)))
                        Text(name).font(.system(size: 13, weight: playing ? .bold : .regular)).foregroundStyle(.white)
                        Spacer()
                        if playing { Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(playing ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(8)
            .frame(width: 210)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.1)))

            VStack(spacing: 8) {
                PreviewView(effects: ["matrix"], logo: "apple-small", showClock: true)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.15)))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                Text("Click a name to preview it").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
    }
}

extension Notification.Name {
    static let showTutorial = Notification.Name("com.applarchy.app.showTutorial")
}
