import SwiftUI

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
        let ink: Color = hovering && isEnabled ? .black : .white
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
        .background(hovering && isEnabled ? Color.white : Color(white: 0.07))
        .overlay(Rectangle().strokeBorder(Color.white.opacity(isEnabled ? 0.9 : 0.3), lineWidth: 2))
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
                Rectangle().fill(Color.white.opacity(hovering ? 0.55 : 0.28))
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
            .foregroundStyle(lit ? Color.black : Color.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(lit ? Color.white : Color(white: 0.1))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .background(Rectangle().fill(Color.white.opacity(0.28)).offset(x: 2, y: 2))
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
                        .foregroundStyle(on ? Color.black : Color.white.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(on ? Color.white : Color(white: 0.1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < options.count - 1 { Rectangle().fill(Color.white.opacity(0.85)).frame(width: 1.5) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5))
        .background(Rectangle().fill(Color.white.opacity(0.28)).offset(x: 2, y: 2))
        .padding(.trailing, 2).padding(.bottom, 2)
    }
}
