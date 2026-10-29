import SwiftUI

/// Logos you've made, newest first. One is added only when you confirm it (USE THIS
/// LOGO), so trying pictures and edits doesn't fill the list.
final class LogoLibrary: ObservableObject {
    static let shared = LogoLibrary()

    struct Logo: Codable, Identifiable, Equatable {
        var id = UUID()
        var art: String
        var saved = Date()
    }

    @Published private(set) var logos: [Logo] = []
    private static let key = "savedLogos"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let saved = try? JSONDecoder().decode([Logo].self, from: data) {
            logos = saved
        } else {
            // First run with a library: keep the custom logos made before it existed.
            for art in [Store.wallpaper?.customLogo, Store.draft.customLogo].compactMap({ $0 }) { add(art) }
        }
    }

    /// A confirmed design: to the top, once (the same art moves up instead).
    func save(_ art: String) {
        add(art)
        persist()
    }

    func remove(_ ids: Set<UUID>) {
        logos.removeAll { ids.contains($0.id) }
        persist()
    }

    private func add(_ art: String) {
        guard !art.allSatisfy(\.isWhitespace) else { return }
        logos.removeAll { $0.art == art }
        logos.insert(Logo(art: art), at: 0)
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(logos), forKey: Self.key)
    }
}

/// Your saved logos as a grid: click one to use it, × to delete it, or SELECT to
/// delete several at once.
struct LogoLibraryView: View {
    @ObservedObject private var library = LogoLibrary.shared
    @Binding var isPresented: Bool
    /// The logo in use, marked in the grid.
    var current: String?
    var onPick: (String) -> Void
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var confirming = false
    @State private var hovered: UUID?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { close() }
            card
                .frame(width: 720)
                .background(Color.surface(0.09))
                .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.85), lineWidth: 2))
                .background(Rectangle().fill(Color.ink.opacity(0.22)).offset(x: 6, y: 6))
        }
        .font(Pixel.body)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("MY LOGOS").font(Pixel.title)
                Text("\(library.logos.count)").foregroundStyle(.secondary)
                Spacer()
                if !library.logos.isEmpty {
                    Button(selecting ? "DONE" : "SELECT") {
                        selecting.toggle()
                        selection = []
                        confirming = false
                    }
                    .buttonStyle(PixelButtonStyle())
                }
            }
            if library.logos.isEmpty {
                Text("No saved logos yet. A logo is saved here when you press USE THIS LOGO in the logo editor.")
                    .foregroundStyle(.secondary).lineSpacing(3)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                PixelScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(library.logos) { tile($0) }
                    }
                    .padding(.trailing, 8).padding(.bottom, 4)
                }
                .frame(height: min(400, CGFloat((library.logos.count + 3) / 4) * 132))
            }
            HStack(spacing: 10) {
                if selecting {
                    Button("ALL") { selection = Set(library.logos.map(\.id)); confirming = false }.buttonStyle(PixelButtonStyle())
                    Button("NONE") { selection = []; confirming = false }.buttonStyle(PixelButtonStyle())
                    Spacer()
                    Button(confirming ? "REALLY DELETE \(selection.count)?" : "DELETE \(selection.count)") {
                        if confirming {
                            library.remove(selection)
                            selection = []
                            confirming = false
                            if library.logos.isEmpty { selecting = false }
                        } else {
                            confirming = true
                        }
                    }
                    .buttonStyle(PixelButtonStyle(prominent: confirming))
                    .disabled(selection.isEmpty)
                } else {
                    Text(library.logos.isEmpty ? "" : "Click a logo to use it · × deletes one").foregroundStyle(.secondary)
                    Spacer()
                    Button("CLOSE") { close() }.buttonStyle(PixelLinkStyle()).keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
    }

    private func tile(_ logo: LogoLibrary.Logo) -> some View {
        let picked = selection.contains(logo.id)
        return LogoThumbnail(logo.art)
            .frame(height: 110)
            .padding(8)
            .background(Color.black)
            .overlay(Rectangle().strokeBorder(picked ? Color.accent : Color.ink.opacity(hovered == logo.id ? 0.7 : 0.25),
                                              lineWidth: picked ? 2.5 : 1.5))
            .overlay(alignment: .topLeading) {
                if selecting { PixelCheckbox(on: picked, ink: .white).padding(8) }
            }
            .overlay(alignment: .bottomLeading) {
                if logo.art == current {
                    Text("IN USE").font(Pixel.body).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accent)
                        .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if !selecting && hovered == logo.id {
                    Button { library.remove([logo.id]) } label: {
                        Text("×").font(Pixel.body).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.black.opacity(0.8))
                            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .help("Delete this logo")
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selecting {
                    if picked { selection.remove(logo.id) } else { selection.insert(logo.id) }
                    confirming = false
                } else {
                    onPick(logo.art)
                    close()
                }
            }
            .onHover { inside in
                if inside { hovered = logo.id } else if hovered == logo.id { hovered = nil }
            }
    }

    private func close() { isPresented = false }
}
