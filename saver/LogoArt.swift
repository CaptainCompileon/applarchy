import AppKit

/// The logo art, drawn at runtime from the system font's Apple character (U+F8FF)
/// rather than shipped as artwork: the glyph is rendered large, cropped to its
/// ink, and resampled into half-block characters (▀ ▄ █), 2 pixels per text cell.
enum LogoArt {
    /// "apple" (Apple Evangelist, 52 columns) or "apple-small" (Chill Guy, 44 columns).
    static func text(named name: String) -> String? {
        switch name {
        case "apple": return render(columns: 52)
        case "apple-small", "screensaver": return render(columns: 44)
        default: return nil
        }
    }

    static func render(columns cols: Int) -> String? {
        let n = 600
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
                                         samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                         colorSpaceName: .deviceWhite, bytesPerRow: n, bitsPerPixel: 8),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: n, height: n).fill()
        NSAttributedString(string: "\u{F8FF}", attributes: [.font: NSFont.systemFont(ofSize: 380), .foregroundColor: NSColor.white])
            .draw(at: NSPoint(x: 100, y: 60))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        // Bitmap rows run top to bottom.
        func ink(_ x: Int, _ y: Int) -> Bool { data[y * rep.bytesPerRow + x] > 127 }
        var minX = n, maxX = 0, minY = n, maxY = 0
        for y in 0..<n { for x in 0..<n where ink(x, y) { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard minX < maxX, minY < maxY else { return nil }
        let bw = Double(maxX - minX + 1), bh = Double(maxY - minY + 1)
        let rowsPx = Int((Double(cols) * bh / bw).rounded())      // half-block pixels are ~square
        func on(_ c: Int, _ r: Int) -> Bool {
            guard r < rowsPx else { return false }
            var hits = 0                                            // 3x3 supersampling, majority vote
            for dy in 0..<3 { for dx in 0..<3 {
                let x = minX + Int((Double(c) + (Double(dx) + 0.5) / 3) * bw / Double(cols))
                let y = minY + Int((Double(r) + (Double(dy) + 0.5) / 3) * bh / Double(rowsPx))
                if ink(min(x, maxX), min(y, maxY)) { hits += 1 }
            }}
            return hits >= 5
        }
        var lines: [String] = []
        var r = 0
        while r < rowsPx {
            var line = ""
            for c in 0..<cols {
                switch (on(c, r), on(c, r + 1)) {
                case (true, true): line += "█"
                case (true, false): line += "▀"
                case (false, true): line += "▄"
                default: line += " "
                }
            }
            while line.hasSuffix(" ") { line.removeLast() }
            lines.append(line)
            r += 2
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
