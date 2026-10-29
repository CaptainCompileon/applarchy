import SwiftUI
import UniformTypeIdentifiers

/// A theme as a small square: its background with the gradient as three pixels.
/// The selected one gets a bright border and a hard shadow.
struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    /// The custom theme before it exists: a "+" instead of its colours.
    var placeholder = false
    let action: () -> Void
    @State private var hovering = false

    private var colors: [Color] {
        let stops = theme.stops.isEmpty ? ["8A008A", "00D1FF", "FFFFFF"] : theme.stops
        return stops.map { Color(hex: UInt32($0, radix: 16) ?? 0) }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if placeholder {
                    Color.surface(0.1)
                    Text("+").font(Pixel.title).foregroundStyle(Color.ink.opacity(0.7))
                } else {
                    Color(hex: theme.background)
                    HStack(spacing: 2) { ForEach(colors.indices, id: \.self) { Rectangle().fill(colors[$0]).frame(width: 5, height: 5) } }
                }
            }
            .frame(width: 26, height: 26)
            .overlay(Rectangle().strokeBorder(Color.ink.opacity(selected ? 0.95 : (hovering ? 0.6 : 0.22)), lineWidth: selected ? 2 : 1))
            .background(Rectangle().fill(Color.ink.opacity(selected ? 0.3 : 0)).offset(x: 2, y: 2))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(placeholder ? "Make your own theme" : theme.name)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// Make your own logo: from a picture (converted to half-block pixels), pasted text
/// art, or a blank canvas, then touched up square by square before use. Shown as a
/// pixel card over the window. Only a confirmed logo goes into My logos.
struct CustomLogoEditor: View {
    @Binding var draft: EffectConfig
    @Binding var isPresented: Bool
    @ObservedObject private var library = LogoLibrary.shared
    @State private var text: String
    /// The text as a grid, with room around it to draw into; kept in step with `text`.
    @State private var art: PixelArt
    @State private var image: CGImage?
    @State private var width = "44"
    @State private var tool = "draw"                 // "draw": the pixel grid; "text": the characters
    @State private var history: [String] = []        // for UNDO
    @State private var showingLibrary = false
    private static let margin = 4

    init(draft: Binding<EffectConfig>, isPresented: Binding<Bool>) {
        _draft = draft
        _isPresented = isPresented
        let text = draft.wrappedValue.customLogo ?? LogoArt.text(named: "apple-small") ?? ""
        _text = State(initialValue: text)
        _art = State(initialValue: PixelArt(text: text).framed(margin: Self.margin))
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
                .frame(width: 900)
                .background(Color.surface(0.09))
                .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.85), lineWidth: 2))
                .background(Rectangle().fill(Color.ink.opacity(0.22)).offset(x: 6, y: 6))
            if showingLibrary {
                LogoLibraryView(isPresented: $showingLibrary, current: text) { picked in
                    image = nil
                    setText(picked)
                }
                .transition(.opacity)
            }
        }
        .font(Pixel.body)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("CUSTOM LOGO").font(Pixel.title)
                Spacer()
                Button("MY LOGOS (\(library.logos.count))…") { showingLibrary = true }.buttonStyle(PixelButtonStyle())
            }
            Text("Choose a picture — a transparent PNG works best — paste text art, or start blank. Click a square to fill or erase it; drag to paint. It goes into My logos when you press USE THIS LOGO.")
                .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("CHOOSE PICTURE…") { choosePicture() }.buttonStyle(PixelButtonStyle())
                Button("PASTE TEXT ART") { if let s = NSPasteboard.general.string(forType: .string) { image = nil; setText(s) } }
                    .buttonStyle(PixelButtonStyle())
                Button("BLANK") { image = nil; setText(""); tool = "draw" }.buttonStyle(PixelButtonStyle())
                Spacer()
                if image != nil {
                    Text("SIZE").foregroundStyle(.secondary)
                    PixelSegmented(selection: Binding(get: { width }, set: { width = $0; convert() }),
                                   options: [("32", "S"), ("44", "M"), ("60", "L")])
                        .frame(width: 130)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        PixelSegmented(selection: $tool, options: [("draw", "DRAW"), ("text", "TEXT")]).frame(width: 170)
                        Spacer()
                        Button("UNDO") { undo() }.buttonStyle(PixelButtonStyle())
                            .keyboardShortcut("z", modifiers: .command)
                            .disabled(history.isEmpty)
                    }
                    Group {
                        if tool == "draw" {
                            PixelCanvas(art: $art, onStroke: { remember() }, onCommit: {
                                text = art.text
                                art = art.framed(margin: Self.margin)             // room again past the new edges
                            })
                        } else {
                            TextEditor(text: $text)
                                .font(.custom("Menlo", size: 7))
                                .foregroundStyle(.white)
                                .modifier(HiddenEditorBackground())
                                .padding(6)
                        }
                    }
                    .background(Color.black)
                    .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.3), lineWidth: 1.5))
                }
                VStack(alignment: .leading, spacing: 6) {
                    // Exactly how the screensaver will draw it (edits restart the preview).
                    PreviewView(effects: ["highlight"], config: previewConfig)
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.3), lineWidth: 1.5))
                    Text("PREVIEW").foregroundStyle(.secondary)
                    original.padding(.top, 8)
                }
                .frame(width: 300)
            }
            .frame(height: 400)
            .onChange(of: text) { new in                         // typed in TEXT: follow it on the grid
                if new != art.text { art = PixelArt(text: new).framed(margin: Self.margin) }
            }
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

    /// The picture chosen while the editor is open, to compare against. Only ever in
    /// memory: closing the editor (or pasting, blanking, picking a saved logo) lets it go.
    private var original: some View {
        VStack(alignment: .leading, spacing: 6) {
            picture
            Text("ORIGINAL PICTURE").foregroundStyle(.secondary)
        }
    }

    private var picture: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                Text("A picture you choose shows here while you edit, to compare. It isn't kept.")
                    .foregroundStyle(.secondary).lineSpacing(3).multilineTextAlignment(.center)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.3), lineWidth: 1.5))
    }

    /// Replace the logo (a picture, paste, blank or saved one), undoably.
    private func setText(_ new: String) {
        guard new != text else { return }
        remember()
        text = new
        art = PixelArt(text: new).framed(margin: Self.margin)
    }

    private func remember() {
        history.append(text)
        if history.count > 100 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        text = last
        art = PixelArt(text: last).framed(margin: Self.margin)
    }

    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let ns = NSImage(contentsOf: url) else { return }
        var rect = CGRect(origin: .zero, size: ns.size)
        image = ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        convert()
        tool = "draw"                                        // straight to touching it up
    }

    /// Convert the picture at the chosen width, narrowing it if it would be taller
    /// than fits comfortably on screen (~36 lines).
    private func convert() {
        guard let image else { return }
        var cols = Int(width) ?? 44
        guard var converted = LogoArt.render(image: image, columns: cols) else { setText(""); return }
        let rows = converted.split(separator: "\n").count
        if rows > 36 {
            cols = max(8, cols * 36 / rows)
            converted = LogoArt.render(image: image, columns: cols) ?? converted
        }
        setText(converted)
    }

    /// Confirmed: this is the logo, and it's kept in My logos.
    private func use() {
        // Trailing spaces and blank lines above and below go; a gap inside the drawing stays.
        var rows = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        while rows.first?.isEmpty == true { rows.removeFirst() }
        while rows.last?.isEmpty == true { rows.removeLast() }
        let logo = rows.joined(separator: "\n") + "\n"
        draft.customLogo = logo
        draft.logo = "custom"
        library.save(logo)
        isPresented = false
    }
}

/// TextEditor draws its own background; hide it where the API exists (macOS 13+).
private struct HiddenEditorBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13, *) { content.scrollContentBackground(.hidden) } else { content }
    }
}

/// Your own theme: a colour for the background and the clock, the gradient the logo settles
/// into, and the effects' accent colours, starting from any built-in theme, with a live preview.
struct CustomThemeEditor: View {
    @Binding var draft: EffectConfig
    @Binding var isPresented: Bool
    @State private var theme: CustomTheme

    init(draft: Binding<EffectConfig>, isPresented: Binding<Bool>) {
        _draft = draft
        _isPresented = isPresented
        let d = draft.wrappedValue
        _theme = State(initialValue: d.customTheme ?? CustomTheme(Themes.named(d.theme)))
    }

    private var previewConfig: EffectConfig {
        var c = draft
        c.theme = "custom"
        c.customTheme = theme
        return c
    }

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
            Text("CUSTOM THEME").font(Pixel.title)
            Text("Pick the colours: the background and clock, the gradient the logo settles into, and the colours the effects use (beams, rain, fireworks, lightning…).")
                .foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    row("BACKGROUND") { well(\.background) }
                    row("CLOCK") { well(\.foreground) }
                    row("GRADIENT") { ForEach(0..<3, id: \.self) { i in well(\.stops, i) } }
                    row("ACCENTS") { ForEach(0..<4, id: \.self) { i in well(\.accents, i) } }
                    row("START FROM") {
                        ForEach(Themes.all) { t in
                            ThemeSwatch(theme: t, selected: false) { theme = CustomTheme(t) }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    // Effects that show the gradient and the accents (edits restart the preview).
                    PreviewView(effects: ["beams", "rain", "fireworks"], config: previewConfig)
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.3), lineWidth: 1.5))
                    Text("PREVIEW").foregroundStyle(.secondary)
                }
                .frame(width: 300)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("CANCEL") { isPresented = false }.buttonStyle(PixelLinkStyle()).keyboardShortcut(.cancelAction)
                Button { use() } label: {
                    Text("USE THIS THEME ▶").font(Pixel.body).foregroundStyle(Color.paper)
                        .padding(.horizontal, 14).padding(.vertical, 7).background(Color.ink)
                }
                .buttonStyle(PixelPressStyle(shadow: 3, hovering: false))
            }
        }
        .padding(24)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            content()
        }
    }

    /// A colour well for one of the theme's hex colours.
    private func well(_ key: WritableKeyPath<CustomTheme, String>) -> some View {
        ColorPicker("", selection: Binding(get: { Color(hex: UInt32(theme[keyPath: key], radix: 16) ?? 0) },
                                           set: { theme[keyPath: key] = Self.hex($0) }), supportsOpacity: false)
            .labelsHidden()
    }

    private func well(_ key: WritableKeyPath<CustomTheme, [String]>, _ i: Int) -> some View {
        ColorPicker("", selection: Binding(get: { Color(hex: UInt32(theme[keyPath: key][i], radix: 16) ?? 0) },
                                           set: { theme[keyPath: key][i] = Self.hex($0) }), supportsOpacity: false)
            .labelsHidden()
    }

    /// "rrggbb" in sRGB, as ttfx takes colours.
    private static func hex(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "000000" }
        func byte(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "%02x%02x%02x", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }

    private func use() {
        draft.customTheme = theme
        draft.theme = "custom"
        isPresented = false
    }
}
