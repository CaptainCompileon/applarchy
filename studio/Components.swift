import SwiftUI

/// The pixel UI's two inks, following the window's appearance: `ink` is white in
/// Dark and black in Light, `paper` the opposite (text on an inverted, ink-filled
/// control). `surface` is a control's fill: the given near-black grey in Dark,
/// mirrored to a near-white one in Light.
extension Color {
    static let ink = Color(nsColor: .appearance(dark: .white, light: .black))
    static let paper = Color(nsColor: .appearance(dark: .black, light: .white))
    static func surface(_ level: CGFloat) -> Color {
        Color(nsColor: .appearance(dark: NSColor(white: level, alpha: 1), light: NSColor(white: 1 - level / 2, alpha: 1)))
    }
}

extension NSColor {
    static func appearance(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
}

/// A large call-to-action in the app's pixel style: near-black with a crisp
/// border, square corners and a hard (unblurred) drop shadow, a pixel-art icon
/// and a monospaced title. Hover inverts it; pressing pushes it into its shadow.
struct BigActionButton: View {
    let title: String
    let subtitle: String
    let icon: PixelIcon
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private let shadow: CGFloat = 4

    var body: some View {
        Button(action: action) { label }
            .buttonStyle(PixelPressStyle(shadow: shadow, hovering: hovering && isEnabled))
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }

    private var label: some View {
        let ink: Color = hovering && isEnabled ? .paper : .ink
        return HStack(spacing: 14) {
            PixelIconView(icon: icon, color: ink).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(Pixel.title)
                Text(subtitle)
                    .font(Pixel.body)
                    .lineLimit(1)
                    .opacity(0.65)
            }
            Spacer(minLength: 0)
            Text("▶").font(Pixel.body).opacity(hovering ? 1 : 0.35)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(hovering && isEnabled ? Color.ink : Color.surface(0.07))
        .overlay(Rectangle().strokeBorder(Color.ink.opacity(isEnabled ? 0.9 : 0.3), lineWidth: 2))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Press = slide into the hard shadow.
struct PixelPressStyle: ButtonStyle {
    let shadow: CGFloat
    let hovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .offset(x: pressed ? shadow : 0, y: pressed ? shadow : 0)
            .background(
                Rectangle().fill(Color.ink.opacity(hovering ? 0.55 : 0.28))
                    .offset(x: shadow, y: shadow)
            )
            .padding(.trailing, shadow).padding(.bottom, shadow)
            .animation(.easeOut(duration: 0.06), value: pressed)
    }
}

/// Tiny pixel-art icons, 12x12, drawn as squares.
enum PixelIcon {
    case moon, storm

    var rows: [String] {
        switch self {
        case .moon: return [
            "..........#.",
            ".........###",
            "..##......#.",
            ".###........",
            ".###........",
            "####........",
            "####........",
            "#####.......",
            ".#####......",
            ".########...",
            "..######....",
            "............",
        ]
        case .storm: return [
            "............",
            "....####....",
            "..########..",
            ".##########.",
            "############",
            "############",
            ".##########.",
            "......#.....",
            ".....##.....",
            "....####....",
            ".....##.....",
            ".....#......",
        ]
        }
    }
}

extension PixelIcon {
    /// The icon as a template image (for the menu bar), one square per pixel.
    func templateImage(points: CGFloat = 18) -> NSImage {
        let grid = rows
        let image = NSImage(size: NSSize(width: points, height: points), flipped: true) { rect in
            let px = floor(rect.width / CGFloat(grid.count) * 2) / 2
            let o = (rect.width - px * CGFloat(grid.count)) / 2
            NSColor.black.setFill()
            for (r, row) in grid.enumerated() {
                for (c, ch) in row.enumerated() where ch == "#" {
                    NSRect(x: o + CGFloat(c) * px, y: o + CGFloat(r) * px, width: px, height: px).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct PixelIconView: View {
    let icon: PixelIcon
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let rows = icon.rows
            let px = floor(min(size.width, size.height) / CGFloat(rows.count))
            let ox = (size.width - px * CGFloat(rows[0].count)) / 2, oy = (size.height - px * CGFloat(rows.count)) / 2
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() where ch == "#" {
                    ctx.fill(Path(CGRect(x: ox + CGFloat(c) * px, y: oy + CGFloat(r) * px, width: px, height: px)), with: .color(color))
                }
            }
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Small pixel-style button: monospaced label, 1.5 px border, hard 2 px shadow; inverts on hover.
struct PixelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PixelButtonBody(configuration: configuration) }
}

private struct PixelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let lit = hovering && isEnabled
        let pressed = configuration.isPressed
        configuration.label
            .font(Pixel.body)
            .foregroundStyle(lit ? Color.paper : Color.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(lit ? Color.ink : Color.surface(0.1))
            .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.85), lineWidth: 1.5))
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .background(Rectangle().fill(Color.ink.opacity(0.28)).offset(x: 2, y: 2))
            .padding(.trailing, 2).padding(.bottom, 2)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.06), value: pressed)
    }
}

/// Pixel-style segmented control.
struct PixelSegmented: View {
    @Binding var selection: String
    let options: [(tag: String, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].tag == selection
                Button { selection = options[i].tag } label: {
                    Text(options[i].title)
                        .font(Pixel.body)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(on ? Color.paper : Color.ink.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(on ? Color.ink : Color.surface(0.1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rectangle().fill(Color.ink.opacity(0.85)).frame(width: 1.5) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.85), lineWidth: 1.5))
        .background(Rectangle().fill(Color.ink.opacity(0.28)).offset(x: 2, y: 2))
        .padding(.trailing, 2).padding(.bottom, 2)
    }
}

/// Pixel checkbox: a 14 pt square with a 1.5 pt border, filled with a solid
/// inner square when on. `ink` is the colour on its background (`.ink`, or
/// `.paper` on an inverted row).
struct PixelCheckbox: View {
    let on: Bool
    var ink: Color = .ink
    var body: some View {
        ZStack {
            Rectangle().strokeBorder(ink.opacity(0.85), lineWidth: 1.5)
            if on { Rectangle().fill(ink).padding(3.5) }
        }
        .frame(width: 14, height: 14)
    }
}

struct PixelCheckboxStyle: ToggleStyle {
    var ink: Color = .ink
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                PixelCheckbox(on: configuration.isOn, ink: ink)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Text-only button that inverts on hover ("SKIP", "?").
struct PixelLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PixelLinkBody(configuration: configuration) }
}

private struct PixelLinkBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    var body: some View {
        configuration.label
            .font(Pixel.body)
            .foregroundStyle(hovering ? Color.paper : Color.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(hovering ? Color.ink : Color.clear)
            .onHover { hovering = $0 }
    }
}

/// A vertical scroll view with a thin, square, monochrome scroll bar in place of
/// the system one.
struct PixelScrollView<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { outer in
            ScrollView(.vertical, showsIndicators: false) {
                content.background(GeometryReader { g in
                    Color.clear.preference(key: ScrollMetrics.self,
                                           value: ScrollMetrics.Value(offset: -g.frame(in: .named("pixelScroll")).minY, height: g.size.height))
                })
            }
            .coordinateSpace(name: "pixelScroll")
            .onPreferenceChange(ScrollMetrics.self) { offset = $0.offset; contentHeight = $0.height }
            .overlay(alignment: .topTrailing) { thumb(viewport: outer.size.height) }
        }
    }

    @ViewBuilder private func thumb(viewport h: CGFloat) -> some View {
        if contentHeight > h + 1 {
            let size = max(28, h * h / contentHeight)
            let y = (h - size) * min(1, max(0, offset / (contentHeight - h)))
            Rectangle().fill(Color.ink.opacity(0.5))
                .frame(width: 3, height: size)
                .offset(x: -2, y: y)
                .allowsHitTesting(false)
        }
    }
}

private struct ScrollMetrics: PreferenceKey {
    struct Value: Equatable { var offset: CGFloat = 0; var height: CGFloat = 0 }
    static var defaultValue = Value()
    static func reduce(value: inout Value, nextValue: () -> Value) { value = nextValue() }
}

extension View {
    /// No blue focus rings anywhere (macOS 14+; earlier systems keep theirs).
    @ViewBuilder func noFocusRing() -> some View {
        if #available(macOS 14, *) { focusEffectDisabled() } else { self }
    }
}
