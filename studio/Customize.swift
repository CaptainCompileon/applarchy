import SwiftUI
import UniformTypeIdentifiers

/// A theme as a small square: its background with the gradient as three pixels.
/// The selected one gets a bright border and a hard shadow.
struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var colors: [Color] {
        let stops = theme.stops.isEmpty ? ["8A008A", "00D1FF", "FFFFFF"] : theme.stops
        return stops.map { Color(hex: UInt32($0, radix: 16) ?? 0) }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Color(hex: theme.background)
                HStack(spacing: 2) { ForEach(colors.indices, id: \.self) { Rectangle().fill(colors[$0]).frame(width: 5, height: 5) } }
            }
            .frame(width: 26, height: 26)
            .overlay(Rectangle().strokeBorder(Color.ink.opacity(selected ? 0.95 : (hovering ? 0.6 : 0.22)), lineWidth: selected ? 2 : 1))
            .background(Rectangle().fill(Color.ink.opacity(selected ? 0.3 : 0)).offset(x: 2, y: 2))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(theme.name)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Make your own logo: from a picture (converted to half-block pixels) or pasted
/// text art, editable before use. Shown as a pixel card over the window.
struct CustomLogoEditor: View {
    @Binding var draft: EffectConfig
    @Binding var isPresented: Bool
    @State private var text: String
    @State private var image: CGImage?
    @State private var width = "44"

    init(draft: Binding<EffectConfig>, isPresented: Binding<Bool>) {
        _draft = draft
        _isPresented = isPresented
        _text = State(initialValue: draft.wrappedValue.customLogo ?? LogoArt.text(named: "apple-small") ?? "")
    }

    private var previewConfig: EffectConfig {
        var c = draft
        c.logo = "custom"
        c.customLogo = text
        c.showClock = false
        return c
    }

    private var lines: [Substring] { text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.allSatisfy(\.isWhitespace) } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture {}
            card
                .frame(width: 760)
                .background(Color.surface(0.09))
                .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.85), lineWidth: 2))
                .background(Rectangle().fill(Color.ink.opacity(0.22)).offset(x: 6, y: 6))
        }
        .font(Pixel.body)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CUSTOM LOGO").font(Pixel.title)
            Text("Choose a picture — a transparent PNG works best — or paste your own text art. It becomes ▀ ▄ █ blocks that every effect animates. You can edit the result below.")
                .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("CHOOSE PICTURE…") { choosePicture() }.buttonStyle(PixelButtonStyle())
                Button("PASTE TEXT ART") { if let s = NSPasteboard.general.string(forType: .string) { image = nil; text = s } }
                    .buttonStyle(PixelButtonStyle())
                Spacer()
                if image != nil {
                    Text("SIZE").foregroundStyle(.secondary)
                    PixelSegmented(selection: Binding(get: { width }, set: { width = $0; convert() }),
                                   options: [("32", "S"), ("44", "M"), ("60", "L")])
                        .frame(width: 130)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                TextEditor(text: $text)
                    .font(.custom("Menlo", size: 7))
                    .foregroundStyle(.white)
                    .modifier(HiddenEditorBackground())
                    .padding(6)
                    .background(Color.black)
                    .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.3), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 6) {
                    // Exactly how the screensaver will draw it (edits restart the preview).
                    PreviewView(effects: ["highlight"], config: previewConfig)
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.3), lineWidth: 1.5))
                    Text("PREVIEW").foregroundStyle(.secondary)
                }
                .frame(width: 300)
            }
            .frame(height: 230)
            HStack(spacing: 10) {
                Text("\(lines.count) LINES × \(lines.map(\.count).max() ?? 0) COLUMNS").foregroundStyle(.secondary)
                Spacer()
                Button("CANCEL") { isPresented = false }.buttonStyle(PixelLinkStyle()).keyboardShortcut(.cancelAction)
                Button { use() } label: {
                    Text("USE THIS LOGO ▶").font(Pixel.body).foregroundStyle(Color.paper)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(Color.ink)
                }
                .buttonStyle(PixelPressStyle(shadow: 3, hovering: false))
                .disabled(lines.isEmpty)
                .opacity(lines.isEmpty ? 0.4 : 1)
            }
        }
        .padding(24)
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let ns = NSImage(contentsOf: url) else { return }
        var rect = CGRect(origin: .zero, size: ns.size)
        image = ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        convert()
    }

    /// Convert the picture at the chosen width, narrowing it if it would be taller
    /// than fits comfortably on screen (~36 lines).
    private func convert() {
        guard let image else { return }
        var cols = Int(width) ?? 44
        guard var art = LogoArt.render(image: image, columns: cols) else { text = ""; return }
        let rows = art.split(separator: "\n").count
        if rows > 36 {
            cols = max(8, cols * 36 / rows)
            art = LogoArt.render(image: image, columns: cols) ?? art
        }
        text = art
    }

    private func use() {
        let trimmed = lines.map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        draft.customLogo = trimmed.joined(separator: "\n") + "\n"
        draft.logo = "custom"
        isPresented = false
    }
}

/// TextEditor draws its own background; hide it where the API exists (macOS 13+).
private struct HiddenEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13, *) { content.scrollContentBackground(.hidden) } else { content }
    }
}
