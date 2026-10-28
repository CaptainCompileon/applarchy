import AppKit
import CoreText
import ScreenSaver
import os.log

/// Applarchy: Omarchy's ttfx effects over the logo in screensaver.txt, drawn as a
/// terminal grid on black. The screensaver itself, and (renamed) the view the app
/// uses for its preview and the live wallpaper.
@objc(ApplarchySaverView)
final class ApplarchySaverView: ScreenSaverView {
    // Settings. The defaults are the screensaver's; the live wallpaper app changes them.

    /// Effects to cycle through, each an effect name optionally followed by its
    /// options ("thunderstorm --storm-time 600").
    var effectCommands: [String] = ApplarchySaverView.effects { didSet { playlist = [] } }
    var showsClock = true
    var clockStyle = ClockStyle()
    /// A theme from Themes (colours of the effects, background and clock).
    var themeID = "omarchy"
    /// Fall back to gentle effects when macOS's Reduce Motion is on.
    var respectsReduceMotion = true
    /// The logo is centred between this fraction of the screen height and the bottom.
    /// nil: just below the clock (or the whole screen without one).
    var logoRegionTop: CGFloat?
    var holdSeconds = 2.0                // pause on the finished logo
    var maxEngineFrames = 30_000         // safety cap for endless effects
    /// Restart the effect when the system screensaver stops (macOS also sends this on lock).
    var followsScreensaverStop = true
    /// When set, draw into an 8-bit offscreen bitmap at this scale and show it as the
    /// layer's contents (scaled up, nearest-neighbour). Far cheaper than redrawing the
    /// window's full-resolution wide-colour backing store every frame; the live
    /// wallpaper uses 1.
    var bitmapScale: CGFloat?
    private var bitmap: CGContext?

    // Omarchy runs ttfx at 120 fps; at 60 Hz that is two engine frames per tick.
    private var engineFramesPerTick: Int { max(1, Int((120 * animationTimeInterval).rounded())) }
    private var holdTicks: Int { max(1, Int((holdSeconds / animationTimeInterval).rounded())) }

    private var saver: OpaquePointer?
    private var engineFrames = 0
    private var holdRemaining = 0
    // Every effect plays once, in random order, before any repeats.
    private static let effects = [
        "beams", "binarypath", "blackhole", "bouncyballs", "bubbles", "burn", "colorshift",
        "crumble", "decrypt", "errorcorrect", "expand", "fireworks", "highlight", "laseretch",
        "matrix", "middleout", "orbittingvolley", "overflow", "pour", "print", "rain",
        "randomsequence", "rings", "scattered", "slice", "slide", "smoke", "spotlights", "spray",
        "swarm", "sweep", "synthgrid", "thunderstorm", "unstable", "vhstape", "waves", "wipe",
    ]
    private var playlist: [String] = []
    private var lastEffect = ""
    private var clockText = ""

    private var cols = 0, rows = 0
    private var cellW: CGFloat = 0, cellH: CGFloat = 0
    private var font: CTFont!
    private var baseline: CGFloat = 0
    private var cells: [Cell] = []
    private var glyphCache: [UInt32: (CTFont, CGGlyph)] = [:]
    /// The furthest any cached glyph's ink reaches outside its cell, in points.
    private var overhang: CGFloat = 0
    private var overhangGrew = false
    /// Logo file in the bundle's Resources, without ".txt".
    var logoName = "screensaver" { didSet { logo = currentLogo() } }
    /// Text art used when logoName is "custom".
    var customLogoText: String? { didSet { if logoName == "custom" { logo = currentLogo() } } }
    private lazy var logo: String = currentLogo()
    private var theme: Theme { Themes.named(themeID) }

    private struct Cell: Equatable { var scalar: UInt32 = 32; var fg: UInt32 = 0xC0C0C0; var bg: UInt32 = 0xFFFF_FFFF }
    private var previous: [Cell] = []

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(willStop),
            name: NSNotification.Name("com.apple.screensaver.willstop"), object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        if let saver { ttfx_saver_free(saver) }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: lifecycle

    override func startAnimation() {
        super.startAnimation()
        applyBundleConfig()
        layoutGrid()
        os_log("start %{public}dx%{public}d grid %{public}dx%{public}d preview=%{public}d", log: Self.log, type: .default,
               Int(bounds.width), Int(bounds.height), cols, rows, isPreview ? 1 : 0)
        startEffect()
    }

    override func stopAnimation() {
        super.stopAnimation()
        endEffect()
    }

    // macOS 14+ keeps legacyScreenSaver instances alive after the saver is
    // dismissed, and also sends willstop when the screen locks while the saver
    // keeps running. So free the effect here, and let animateOneFrame decide
    // from the window whether to carry on (a new effect) or stay idle.
    @objc private func willStop(_ note: Notification) {
        guard followsScreensaverStop else { return }
        os_log("willstop (preview=%{public}d)", log: Self.log, type: .default, isPreview ? 1 : 0)
        endEffect()
        holdRemaining = 0
    }

    private static let log = OSLog(subsystem: "com.applarchy.screensaver", category: "saver")

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if isAnimating { layoutGrid(); startEffect() }
    }

    // MARK: effect

    private func layoutGrid() {
        // Font size 18 on a 1512 x 982 pt screen (Omarchy's screensaver size), scaled to the view.
        let size = max(3, 18 * layoutScale(bounds))
        font = CTFontCreateWithName("Menlo-Regular" as CFString, size, nil)
        var glyph = CGGlyph(0)
        var m: UniChar = 0x4D
        CTFontGetGlyphsForCharacters(font, &m, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        cellW = advance.width
        cellH = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        baseline = (cellH - CTFontGetAscent(font) - CTFontGetDescent(font)) / 2 + CTFontGetAscent(font)
        cols = max(1, Int(bounds.width / cellW))
        rows = max(1, Int(bounds.height / cellH))
        cells = Array(repeating: Cell(), count: cols * rows)
        previous = []
        glyphCache.removeAll()
        overhang = 0
        makeBitmap()
        invalidateAll()
    }

    /// Effects that stay calm (no flying, exploding or flashing characters).
    private static let gentleEffects: Set<String> = ["colorshift", "expand", "highlight", "middleout", "print", "randomsequence", "sweep", "wipe"]

    private func nextEffectName() -> String {
        if let forced = ProcessInfo.processInfo.environment["OMARCHY_EFFECT"] { return forced }  // testing
        var pool = effectCommands
        if respectsReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            pool = pool.filter { Self.gentleEffects.contains(String($0.split(separator: " ").first ?? "")) }
            if pool.isEmpty { pool = ["highlight", "colorshift", "wipe"] }
            playlist.removeAll { !pool.contains($0) }
        }
        if playlist.isEmpty {
            playlist = pool.shuffled()
            if playlist.count > 1, playlist.first == lastEffect { playlist.swapAt(0, playlist.count - 1) }
        }
        lastEffect = playlist.removeFirst()
        return lastEffect
    }

    private func startEffect() {
        endEffect()
        let text = logo
        let height = Int32(rows + logoLayout().extra)   // rows past the screen are never drawn
        let seed = UInt64.random(in: 1...UInt64.max)
        // Fall back to a random pick if a named effect can't be built.
        let name = theme.command(for: nextEffectName())
        saver = text.withCString { t in name.withCString { ttfx_saver_new_named(t, Int32(cols), height, seed, $0) } }
            ?? text.withCString { ttfx_saver_new($0, Int32(cols), height, seed) }
        os_log("effect %{public}@ %{public}@", log: Self.log, type: .default, name, saver == nil ? "FAILED" : "ok")
        engineFrames = 0
        holdRemaining = 0
    }

    private func endEffect() {
        if let saver { ttfx_saver_free(saver) }
        saver = nil
    }

    override func animateOneFrame() {
        if showsClock {
            let now = PixelClock.timeString(clockStyle)
            if now != clockText { clockText = now; invalidateAll() }
        }
        if holdRemaining > 0 {
            holdRemaining -= 1
            if holdRemaining == 0 { startEffect() }
            return
        }
        guard let saver else { startEffect(); return }
        var frame: UnsafePointer<UInt8>?
        var len = 0
        var finished = false
        for _ in 0..<engineFramesPerTick {
            // A null return leaves the last frame (and len) intact: still draw it.
            guard let next = ttfx_saver_next(saver, &len) else { finished = true; break }
            frame = next
            engineFrames += 1
        }
        if let frame {
            if previous.count != cells.count { previous = cells }
            swap(&previous, &cells)              // previous = last frame
            parse(UnsafeBufferPointer(start: frame, count: len))
            invalidateChangedCells()
        }
        if finished || engineFrames >= maxEngineFrames {
            endEffect()
            holdRemaining = holdTicks
        }
    }

    // MARK: ANSI frame -> cells

    private func invalidate(_ rect: CGRect) {
        if let bitmap {
            render(rect, in: bitmap)
            needsDisplay = true      // -> updateLayer
        } else {
            setNeedsDisplay(rect)
        }
    }

    private func invalidateAll() { invalidate(bounds) }

    private func makeBitmap() {
        guard let scale = bitmapScale, bounds.width > 0, bounds.height > 0 else { bitmap = nil; return }
        let w = Int(bounds.width * scale), h = Int(bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  // the display's own colour space, so the compositor doesn't convert every frame
                                  space: window?.screen?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { bitmap = nil; return }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)     // same flipped coordinates as the view
        bitmap = ctx
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { bitmapScale != nil }

    override func updateLayer() {
        guard let layer, let image = bitmap?.makeImage() else { return }
        layer.magnificationFilter = .nearest
        layer.contentsGravity = .resize
        layer.contents = image
    }

    private var gridOrigin: CGPoint {
        CGPoint(x: floor((bounds.width - CGFloat(cols) * cellW) / 2), y: floor((bounds.height - CGFloat(rows) * cellH) / 2))
    }

    /// Redraw only the cells that differ from the last frame (padded a cell each
    /// side for glyphs that overhang their cell). Drawing into our own bitmap, an
    /// extra rect is cheap but every pixel costs, so redraw just the runs of changed
    /// cells. Drawing into the window, each dirty rect is costly to composite, so
    /// take a run per row and merge overlapping runs on consecutive rows into one
    /// band: effects that change most of the screen (matrix) then redraw a few
    /// large rects, not one per row.
    private func invalidateChangedCells() {
        guard previous.count == cells.count, !overhangGrew else { overhangGrew = false; invalidateAll(); return }
        let o = gridOrigin
        // Padded for glyphs that overhang their cell: a cell's width sideways (plus any
        // more some glyph reaches), and the reach above and below. Whole points: a
        // fractional clip sends every fill down CoreGraphics' slow masked path.
        let padX = max(1, overhang - cellW), padY = max(1, overhang)
        func invalidateCells(rows r0: Int, _ r1: Int, cols c0: Int, _ c1: Int) {
            let c0 = max(0, c0 - 1), c1 = min(cols - 1, c1 + 1)
            invalidate(NSRect(x: o.x + CGFloat(c0) * cellW - padX, y: o.y + CGFloat(r0) * cellH - padY,
                              width: CGFloat(c1 - c0 + 1) * cellW + 2 * padX, height: CGFloat(r1 - r0 + 1) * cellH + 2 * padY).integral)
        }
        var band: (r0: Int, r1: Int, c0: Int, c1: Int)?
        func flush() {
            if let b = band { invalidateCells(rows: b.r0, b.r1, cols: b.c0, b.c1) }
            band = nil
        }
        var runs: [(first: Int, last: Int)] = []
        cells.withUnsafeBufferPointer { now in
            previous.withUnsafeBufferPointer { old in
                for r in 0..<rows {
                    let base = r * cols
                    runs.removeAll(keepingCapacity: true)
                    for c in 0..<cols where now[base + c] != old[base + c] {
                        if let run = runs.last, c - run.last <= 4 { runs[runs.count - 1].last = c } else { runs.append((c, c)) }
                    }
                    guard let first = runs.first?.first, let last = runs.last?.last else { flush(); continue }
                    if bitmap != nil {
                        for run in runs { invalidateCells(rows: r, r, cols: run.first, run.last) }
                        continue
                    }
                    if let b = band, first <= b.c1 + 2, last >= b.c0 - 2 {     // overlapping once padded
                        band = (b.r0, r, min(b.c0, first), max(b.c1, last))
                    } else {
                        flush()
                        band = (r, r, first, last)
                    }
                }
            }
        }
        flush()
    }

    private func parse(_ bytes: UnsafeBufferPointer<UInt8>) {
        var row = 0, col = 0
        var fg: UInt32 = 0xC0C0C0, bg: UInt32 = 0xFFFF_FFFF
        var i = 0
        let n = bytes.count
        var params: [Int] = []          // reused: a frame has thousands of escape sequences
        for k in cells.indices { cells[k] = Cell() }
        while i < n {
            let b = bytes[i]
            if b == 0x1B {
                i += 1
                guard i < n else { break }
                if bytes[i] != UInt8(ascii: "[") { i += 1; continue }   // ESC 7 / ESC 8
                i += 1
                params.removeAll(keepingCapacity: true)
                var cur = 0, has = false
                while i < n {
                    let c = bytes[i]
                    if c >= 0x30 && c <= 0x39 { cur = cur * 10 + Int(c - 0x30); has = true }
                    else if c == UInt8(ascii: ";") { params.append(has ? cur : 0); cur = 0; has = false }
                    else if c == UInt8(ascii: "?") {}
                    else { break }
                    i += 1
                }
                if has { params.append(cur) }
                guard i < n else { break }
                let final = bytes[i]
                i += 1
                if final == UInt8(ascii: "m") { applySGR(params, &fg, &bg) }
                continue
            }
            if b == 0x0A { row += 1; col = 0; i += 1; continue }
            if b == 0x0D { col = 0; i += 1; continue }
            // UTF-8 decode one scalar
            var scalar = UInt32(b), extra = 0
            if b >= 0xF0 { scalar = UInt32(b & 0x07); extra = 3 }
            else if b >= 0xE0 { scalar = UInt32(b & 0x0F); extra = 2 }
            else if b >= 0xC0 { scalar = UInt32(b & 0x1F); extra = 1 }
            i += 1
            while extra > 0 && i < n { scalar = (scalar << 6) | UInt32(bytes[i] & 0x3F); i += 1; extra -= 1 }
            if row < rows && col < cols { cells[row * cols + col] = Cell(scalar: scalar, fg: fg, bg: bg) }
            col += 1
        }
    }

    private func applySGR(_ p: [Int], _ fg: inout UInt32, _ bg: inout UInt32) {
        if p.isEmpty { fg = 0xC0C0C0; bg = 0xFFFF_FFFF; return }
        var j = 0
        while j < p.count {
            switch p[j] {
            case 0: fg = 0xC0C0C0; bg = 0xFFFF_FFFF
            case 39: fg = 0xC0C0C0
            case 49: bg = 0xFFFF_FFFF
            case 38, 48:
                if j + 4 < p.count && p[j + 1] == 2 {
                    let rgb = UInt32(p[j + 2] & 0xFF) << 16 | UInt32(p[j + 3] & 0xFF) << 8 | UInt32(p[j + 4] & 0xFF)
                    if p[j] == 38 { fg = rgb } else { bg = rgb }
                    j += 4
                } else if j + 2 < p.count && p[j + 1] == 5 {
                    j += 2
                }
            default: break
            }
            j += 1
        }
    }

    // MARK: drawing

    override func draw(_ rect: NSRect) {
        guard bitmap == nil, let ctx = NSGraphicsContext.current?.cgContext else { return }
        render(rect, in: ctx)
    }

    /// Paint `rect` (view coordinates, flipped) into `ctx`.
    private func render(_ rect: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: rect)
        let bg = theme.background
        ctx.setFillColor(CGColor(red: CGFloat(bg >> 16 & 0xFF) / 255, green: CGFloat(bg >> 8 & 0xFF) / 255, blue: CGFloat(bg & 0xFF) / 255, alpha: 1))
        ctx.fill(rect)
        guard !cells.isEmpty else { return }
        ctx.textMatrix = .identity
        ctx.setShouldAntialias(true)
        let ox = gridOrigin.x, oy = gridOrigin.y
        // Only the cells under the dirty rect (plus one either side for overhanging glyphs).
        let r0 = max(0, Int(floor((rect.minY - oy) / cellH)) - 1), r1 = min(rows - 1, Int(ceil((rect.maxY - oy) / cellH)))
        let c0 = max(0, Int(floor((rect.minX - ox) / cellW)) - 1), c1 = min(cols - 1, Int(ceil((rect.maxX - ox) / cellW)))
        guard r0 <= r1, c0 <= c1 else { return }
        for r in r0...r1 {
            let y0 = round(oy + CGFloat(r) * cellH), y1 = round(oy + CGFloat(r + 1) * cellH)
            for c in c0...c1 {
                let cell = cells[r * cols + c]
                let x0 = round(ox + CGFloat(c) * cellW), x1 = round(ox + CGFloat(c + 1) * cellW)
                let box = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
                if cell.bg != 0xFFFF_FFFF { ctx.setFillColor(color(cell.bg)); ctx.fill(box) }
                if cell.scalar == 32 || cell.scalar == 0 { continue }
                ctx.setFillColor(color(cell.fg))
                if drawBlock(cell.scalar, in: box, ctx) { continue }
                guard let (f, g) = glyph(for: cell.scalar) else { continue }
                // The view is flipped; flip each glyph back around its baseline.
                // (A flipped text matrix instead makes Core Text draw nothing here.)
                var glyph = g
                var origin = CGPoint.zero
                ctx.saveGState()
                ctx.translateBy(x: x0, y: y0 + baseline)
                ctx.scaleBy(x: 1, y: -1)
                CTFontDrawGlyphs(f, &glyph, &origin, 1, ctx)
                ctx.restoreGState()
            }
        }
        // The clock sits midway between the top of the screen and the top of the logo.
        if showsClock {
            var style = clockStyle
            style.color = theme.foreground
            PixelClock.draw(in: bounds, top: round((logoTop - PixelClock.height(in: bounds, style: clockStyle)) / 2), style: style, ctx)
        }
    }

    /// Colours by RGB value: every drawn cell needs one, and creating them was a
    /// quarter of the drawing time. Effects fade through many shades, hence the cap.
    private var colorCache: [UInt32: CGColor] = [:]

    private func color(_ rgb: UInt32) -> CGColor {
        if let hit = colorCache[rgb] { return hit }
        if colorCache.count >= 4096 { colorCache.removeAll(keepingCapacity: true) }
        let c = CGColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                        blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        colorCache[rgb] = c
        return c
    }

    /// Block elements (U+2580–U+259F) as exact rectangles, so the logo has no seams.
    private func drawBlock(_ s: UInt32, in b: CGRect, _ ctx: CGContext) -> Bool {
        let w = b.width, h = b.height
        func fill(_ x: CGFloat, _ y: CGFloat, _ fw: CGFloat, _ fh: CGFloat) {
            ctx.fill(CGRect(x: b.minX + round(x * w), y: b.minY + round(y * h),
                            width: round((x + fw) * w) - round(x * w), height: round((y + fh) * h) - round(y * h)))
        }
        switch s {
        case 0x2580: fill(0, 0, 1, 0.5)
        case 0x2581...0x2587: let f = CGFloat(s - 0x2580) / 8; fill(0, 1 - f, 1, f)
        case 0x2588: fill(0, 0, 1, 1)
        case 0x2589...0x258F: let f = CGFloat(0x2590 - s) / 8; fill(0, 0, f, 1)
        case 0x2590: fill(0.5, 0, 0.5, 1)
        case 0x2591...0x2593:
            ctx.saveGState(); ctx.setAlpha(CGFloat(s - 0x2590) / 4); fill(0, 0, 1, 1); ctx.restoreGState()
        case 0x2594: fill(0, 0, 1, 0.125)
        case 0x2595: fill(0.875, 0, 0.125, 1)
        case 0x2596...0x259F:
            // quadrants: bits = upper-left, upper-right, lower-left, lower-right
            let q: [UInt8] = [0b0010, 0b0001, 0b1000, 0b1011, 0b1001, 0b1110, 0b1101, 0b0100, 0b0110, 0b0111]
            let m = q[Int(s - 0x2596)]
            if m & 0b1000 != 0 { fill(0, 0, 0.5, 0.5) }
            if m & 0b0100 != 0 { fill(0.5, 0, 0.5, 0.5) }
            if m & 0b0010 != 0 { fill(0, 0.5, 0.5, 0.5) }
            if m & 0b0001 != 0 { fill(0.5, 0.5, 0.5, 0.5) }
        default: return false
        }
        return true
    }

    private func glyph(for scalar: UInt32) -> (CTFont, CGGlyph)? {
        if let hit = glyphCache[scalar] { return hit.1 == 0 ? nil : hit }
        guard let u = Unicode.Scalar(scalar) else { return nil }
        let str = String(Character(u))
        var units = Array(str.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        var f: CTFont = font
        if !CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) {
            f = CTFontCreateForString(font, str as CFString, CFRange(location: 0, length: units.count))
            CTFontGetGlyphsForCharacters(f, &units, &glyphs, units.count)
        }
        glyphCache[scalar] = (f, glyphs[0])
        guard glyphs[0] != 0 else { return nil }
        // Glyphs from fallback fonts can be taller or wider than a cell; dirty rects
        // are padded by the most any glyph seen so far reaches outside its cell.
        var ink = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(f, .horizontal, &glyphs, &ink, 1)
        let below = cellH - baseline        // cell space under the baseline
        let reach = ceil(max(ink.maxY - baseline, -ink.minY - below, -ink.minX, ink.maxX - cellW))
        // It was just clipped to a rect padded for less: redraw everything next frame.
        if reach > overhang { overhang = reach; overhangGrew = true }
        return (f, glyphs[0])
    }

    // MARK: logo

    private var logoCentre: CGFloat {
        // Below the clock: the clock block plus 38 pt of margin (on a 1512 x 982 pt screen).
        let top = logoRegionTop.map { bounds.height * $0 }
            ?? (showsClock ? 38 * layoutScale(bounds) + PixelClock.height(in: bounds, style: clockStyle) : 0)
        return (top + bounds.height) / 2
    }

    /// ttfx centres the logo in its canvas (top row = floor(height / 2) - ceil(lines / 2)).
    /// Giving it a canvas `extra` rows taller than the screen, and showing only the
    /// top `rows`, moves the logo down half a row per extra row while the effects
    /// still cover the whole screen. Pick the `extra` that puts the logo's centre
    /// closest to logoCentre, and report the row its top lands on.
    private func logoLayout() -> (extra: Int, topRow: Int) {
        let oy = floor((bounds.height - CGFloat(rows) * cellH) / 2)
        let lines = logo.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        var best = (extra: 0, topRow: max(0, (rows - lines) / 2), err: CGFloat.infinity)
        for extra in 0...max(0, rows - lines) {
            let topRow = (rows + extra) / 2 - (lines + 1) / 2   // measured: floor(height/2) - ceil(lines/2)
            let err = abs(oy + (CGFloat(topRow) + CGFloat(lines) / 2) * cellH - logoCentre)
            if err < best.err { best = (extra, topRow, err) }
        }
        return (best.extra, best.topRow)
    }

    /// Top of the logo as drawn, for placing the clock above it.
    private var logoTop: CGFloat {
        floor((bounds.height - CGFloat(rows) * cellH) / 2) + CGFloat(logoLayout().topRow) * cellH
    }

    /// The built-in logos are drawn from the system font at runtime (see LogoArt);
    /// any other name is read from Resources/<name>.txt.
    private func currentLogo() -> String {
        if logoName == "custom", let text = customLogoText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        return Self.loadLogo(named: logoName == "custom" ? "apple-small" : logoName)
    }

    private static func loadLogo(named name: String) -> String {
        if let art = LogoArt.text(named: name) { return art }
        let resources = Bundle(for: ApplarchySaverView.self).resourceURL
        for file in [name, "screensaver"] {
            if let url = resources?.appendingPathComponent(file + ".txt"),
               let s = try? String(contentsOf: url, encoding: .utf8) {
                return s
            }
        }
        return "omarchy"
    }

    /// Settings Applarchy writes into the screensaver bundle (Resources/config.json):
    /// {"effects": [...], "logo": "apple" | "apple-small", "showClock": true}.
    /// Read straight from disk on every start, so changes apply the next time
    /// the screensaver runs.
    private func applyBundleConfig() {
        guard let url = Bundle(for: ApplarchySaverView.self).resourceURL?.appendingPathComponent("config.json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let effects = config["effects"] as? [String], !effects.isEmpty, effects != effectCommands { effectCommands = effects }
        if let text = config["customLogo"] as? String { customLogoText = text }
        if let name = config["logo"] as? String, name != logoName { logoName = name }
        if let clock = config["showClock"] as? Bool { showsClock = clock }
        if let theme = config["theme"] as? String { themeID = theme }
        if let cycle = config["hourCycle"] as? String { clockStyle.hourCycle = cycle }
        if let date = config["showDate"] as? Bool { clockStyle.showDate = date }
        if let large = config["clockLarge"] as? Bool { clockStyle.large = large }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
