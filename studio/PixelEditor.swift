import SwiftUI

/// A logo as pixels. Logos are half-block text (▀ ▄ █), two pixels to a text cell,
/// stacked; this is that text as a grid you can click. Any other character (pasted
/// text art) counts as a full cell.
struct PixelArt: Equatable {
    private(set) var width: Int
    private(set) var height: Int                 // pixel rows; always even
    private var pixels: [Bool]                   // row by row, top first

    init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(2, height + height % 2)
        pixels = Array(repeating: false, count: self.width * self.height)
    }

    init(text: String) {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(Array.init)
        while lines.last?.allSatisfy(\.isWhitespace) == true { lines.removeLast() }
        self.init(width: lines.map(\.count).max() ?? 0, height: lines.count * 2)
        for (row, line) in lines.enumerated() {
            for (x, c) in line.enumerated() {
                let (top, bottom): (Bool, Bool) = switch c {
                case "▀": (true, false)
                case "▄": (false, true)
                case _ where c.isWhitespace: (false, false)
                default: (true, true)                // █ and any other character
                }
                self[x, row * 2] = top
                self[x, row * 2 + 1] = bottom
            }
        }
    }

    subscript(x: Int, y: Int) -> Bool {
        get { contains(x, y) && pixels[y * width + x] }
        set { if contains(x, y) { pixels[y * width + x] = newValue } }
    }

    func contains(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height }

    var isEmpty: Bool { !pixels.contains(true) }

    /// The drawn pixels' bounds, or nil when nothing is drawn.
    private var ink: (minX: Int, maxX: Int, minY: Int, maxY: Int)? {
        var b: (minX: Int, maxX: Int, minY: Int, maxY: Int)?
        for y in 0..<height { for x in 0..<width where self[x, y] {
            b = (min(b?.minX ?? x, x), max(b?.maxX ?? x, x), min(b?.minY ?? y, y), max(b?.maxY ?? y, y))
        }}
        return b
    }

    /// Cropped to the drawing, then `margin` empty pixels on every side (an even number
    /// above and below, so the text rows stay paired), at most `maxWidth` × `maxHeight`:
    /// room to draw past the edges.
    func framed(margin: Int, maxWidth: Int = 100, maxHeight: Int = 72) -> PixelArt {
        guard let b = ink else { return PixelArt(width: 32, height: 32) }        // a blank canvas
        let w = b.maxX - b.minX + 1, h = b.maxY - b.minY + 1
        let mx = max(0, min(margin, (maxWidth - w) / 2))
        let my = max(0, min(margin, (maxHeight - h) / 2)) / 2 * 2
        var out = PixelArt(width: w + 2 * mx, height: h + 2 * my)
        for y in b.minY...b.maxY { for x in b.minX...b.maxX where self[x, y] { out[x - b.minX + mx, y - b.minY + my] = true } }
        return out
    }

    /// Back to half-block text, cropped to the drawing ("" when it's empty).
    var text: String {
        guard let b = ink else { return "" }
        var lines: [String] = []
        for y in stride(from: b.minY, through: b.maxY, by: 2) {
            var line = ""
            for x in b.minX...b.maxX {
                switch (self[x, y], self[x, y + 1]) {
                case (true, true): line += "█"
                case (true, false): line += "▀"
                case (false, true): line += "▄"
                default: line += " "
                }
            }
            while line.hasSuffix(" ") { line.removeLast() }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Click a square to fill it or, if it's filled, erase it; drag to keep filling or
/// erasing. `onStroke` comes before each click or drag (for undo); the finished
/// stroke is in `art` when `onCommit` runs.
struct PixelCanvas: View {
    @Binding var art: PixelArt
    var onStroke: () -> Void = {}
    var onCommit: () -> Void = {}
    @State private var painting: (value: Bool, last: (x: Int, y: Int))?
    @State private var hover: (x: Int, y: Int)?

    var body: some View {
        GeometryReader { g in
            let layout = Layout(art: art, size: g.size)
            Canvas { ctx, _ in
                ctx.fill(Path(layout.frame), with: .color(.black))
                for y in 0..<art.height { for x in 0..<art.width where art[x, y] {
                    ctx.fill(Path(layout.rect(x, y)), with: .color(.white))
                }}
                if layout.cell >= 5 {                    // a faint grid, when squares are big enough to aim at
                    var grid = Path()
                    for x in 0...art.width { let px = layout.frame.minX + CGFloat(x) * layout.cell
                        grid.move(to: CGPoint(x: px, y: layout.frame.minY)); grid.addLine(to: CGPoint(x: px, y: layout.frame.maxY)) }
                    for y in 0...art.height { let py = layout.frame.minY + CGFloat(y) * layout.cell
                        grid.move(to: CGPoint(x: layout.frame.minX, y: py)); grid.addLine(to: CGPoint(x: layout.frame.maxX, y: py)) }
                    ctx.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
                if let hover, art.contains(hover.x, hover.y) {
                    ctx.stroke(Path(layout.rect(hover.x, hover.y).insetBy(dx: 0.75, dy: 0.75)), with: .color(Color.accent), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard let p = layout.pixel(at: drag.location) else { return }
                if let stroke = painting {
                    line(from: stroke.last, to: p) { art[$0, $1] = stroke.value }   // no gaps on a quick drag
                    painting = (stroke.value, p)
                } else {
                    onStroke()
                    let value = !art[p.x, p.y]                                      // the first square decides: fill or erase
                    art[p.x, p.y] = value
                    painting = (value, p)
                }
                hover = p
            }.onEnded { _ in
                guard painting != nil else { return }
                painting = nil
                onCommit()
            })
            .onContinuousHover { phase in
                if case .active(let at) = phase { hover = layout.pixel(at: at) } else { hover = nil }
            }
        }
    }

    /// Squares as large as fit, centred.
    private struct Layout {
        let cell: CGFloat
        let frame: CGRect
        let art: PixelArt
        init(art: PixelArt, size: CGSize) {
            self.art = art
            cell = max(1, floor(min(size.width / CGFloat(art.width), size.height / CGFloat(art.height))))
            let w = cell * CGFloat(art.width), h = cell * CGFloat(art.height)
            frame = CGRect(x: floor((size.width - w) / 2), y: floor((size.height - h) / 2), width: w, height: h)
        }
        func rect(_ x: Int, _ y: Int) -> CGRect {
            CGRect(x: frame.minX + CGFloat(x) * cell, y: frame.minY + CGFloat(y) * cell, width: cell, height: cell)
        }
        func pixel(at p: CGPoint) -> (x: Int, y: Int)? {
            let x = Int(floor((p.x - frame.minX) / cell)), y = Int(floor((p.y - frame.minY) / cell))
            return art.contains(x, y) ? (x, y) : nil
        }
    }

    /// Every square on the line between two (Bresenham).
    private func line(from a: (x: Int, y: Int), to b: (x: Int, y: Int), _ visit: (Int, Int) -> Void) {
        var (x, y) = a
        let dx = abs(b.x - x), dy = -abs(b.y - y), sx = x < b.x ? 1 : -1, sy = y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            visit(x, y)
            if x == b.x && y == b.y { return }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
    }
}

/// A saved logo, small: its pixels scaled to fit, white on black.
struct LogoThumbnail: View {
    let art: PixelArt
    init(_ text: String) { art = PixelArt(text: text).framed(margin: 2) }
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let cell = min(size.width / CGFloat(art.width), size.height / CGFloat(art.height))
            let ox = (size.width - cell * CGFloat(art.width)) / 2, oy = (size.height - cell * CGFloat(art.height)) / 2
            var path = Path()
            for y in 0..<art.height { for x in 0..<art.width where art[x, y] {
                path.addRect(CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell, width: cell, height: cell))
            }}
            ctx.fill(path, with: .color(.white))
        }
    }
}
