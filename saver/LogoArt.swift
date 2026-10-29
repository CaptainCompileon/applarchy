import AppKit

/// The logo art, drawn at runtime from the system font's Apple character (U+F8FF)
/// rather than shipped as artwork: the glyph is rendered large, cropped to its
/// ink, and resampled into half-block characters (▀ ▄ █), 2 pixels per text cell.
enum LogoArt {
    /// "apple-small" (Chill Guy, 44 columns). "apple", the retired Apple Evangelist,
    /// draws the same, for settings saved before it went.
    static func text(named name: String) -> String? {
        switch name {
        case "apple-small", "apple", "screensaver": return render(columns: 44)
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
        let stride = rep.bytesPerRow
        return halfBlocks(width: n, height: n, columns: cols) { x, y in data[y * stride + x] > 127 }
    }

    /// Any picture as half-block art: transparent images by their alpha, opaque ones
    /// by contrast against the colour in their top-left corner.
    static func render(image: CGImage, columns cols: Int) -> String? {
        let w = min(image.width, 800), h = Int(Double(image.height) * Double(w) / Double(image.width))
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let _ = ctx.data else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        func at(_ x: Int, _ y: Int) -> (l: Double, a: Double) {      // rows top to bottom
            let i = (y * w + x) * 4
            let a = Double(px[i + 3]) / 255
            guard a > 0 else { return (0, 0) }
            let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
            return (0.2126 * r + 0.7152 * g + 0.0722 * b, a)
        }
        var transparent = false
        for y in Swift.stride(from: 0, to: h, by: 4) { for x in Swift.stride(from: 0, to: w, by: 4) where at(x, y).a < 0.5 { transparent = true; break } }
        let corner = at(0, 0).l
        return halfBlocks(width: w, height: h, columns: cols) { x, y in
            let p = at(x, y)
            return transparent ? p.a >= 0.5 : abs(p.l - corner) > 0.25
        }
    }

    /// Crop to the ink and resample into half-block characters (▀ ▄ █), 2 pixels per
    /// text cell, `cols` wide; 3x3 supersampling with a majority vote per pixel.
    private static func halfBlocks(width n: Int, height m: Int, columns cols: Int, ink: (Int, Int) -> Bool) -> String? {
        var minX = n, maxX = 0, minY = m, maxY = 0
        for y in 0..<m { for x in 0..<n where ink(x, y) { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard minX < maxX, minY < maxY else { return nil }
        let bw = Double(maxX - minX + 1), bh = Double(maxY - minY + 1)
        let rowsPx = Int((Double(cols) * bh / bw).rounded())      // half-block pixels are ~square
        func on(_ c: Int, _ r: Int) -> Bool {
            guard r < rowsPx else { return false }
            var hits = 0
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
