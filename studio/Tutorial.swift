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
                .background(Color(white: 0.09))
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.85), lineWidth: 2))
                .background(Rectangle().fill(Color.white.opacity(0.22)).offset(x: 6, y: 6))   // hard pixel shadow
                .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
        }
        .font(Pixel.body)
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
            .clipped()
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5))
            .padding([.horizontal, .top], 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("STEP \(page + 1) OF \(steps.count)")
                    .font(Pixel.body)
                    .foregroundStyle(.secondary)
                Text(steps[page].title).font(Pixel.display)
                Text(steps[page].body).font(Pixel.body).lineSpacing(4).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 54, alignment: .top)
            }
            .id("text\(page)")
            .transition(.opacity)
            .padding(.horizontal, 24).padding(.top, 18)

            HStack {
                Button("SKIP") { close() }
                    .buttonStyle(PixelLinkStyle())
                    .keyboardShortcut(.cancelAction)
                    .opacity(page == steps.count - 1 ? 0 : 1)
                Spacer()
                HStack(spacing: 7) {
                    ForEach(steps.indices, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i == page ? 1 : 0.25))
                            .frame(width: i == page ? 20 : 6, height: 6)
                            .onTapGesture { go(to: i) }
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    if page > 0 {
                        Button { go(to: page - 1) } label: {
                            Text("◀").font(Pixel.body)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Color(white: 0.14))
                                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.8), lineWidth: 2))
                        }
                        .buttonStyle(PixelPressStyle(shadow: 3, hovering: false))
                    }
                    Button { page == steps.count - 1 ? close() : go(to: page + 1) } label: {
                        Text((page == steps.count - 1 ? "GET STARTED" : "NEXT") + " ▶")
                            .font(Pixel.body)
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
                .overlay(alignment: .bottomLeading) { Badge(text: "● LIVE").padding(12) }
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
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            Text(title.uppercased()).font(Pixel.body).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct Badge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Pixel.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color.black.opacity(0.7))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
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
                        PixelCheckbox(on: on, ink: playing ? .black : .white)
                        Text(name).font(Pixel.body).foregroundStyle(playing ? Color.black : Color.white.opacity(0.85))
                        Spacer()
                        if playing { Text("▶").font(Pixel.body).foregroundStyle(.black) }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(playing ? Color.white : Color.clear)
                }
            }
            .padding(8)
            .frame(width: 210)
            .background(Color.white.opacity(0.04))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))

            VStack(spacing: 8) {
                PreviewView(effects: ["matrix"], logo: "apple-small", showClock: true)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .overlay(Rectangle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
                Text("Click a name to preview it").font(Pixel.body).foregroundStyle(.white.opacity(0.7))
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
