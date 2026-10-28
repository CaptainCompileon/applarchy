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
    /// Draw the clock (layout still makes room for it when showsClock is on).
    var clockVisible = true

    // MARK: smooth mode
    //
    // The screensaver announces every effect it starts (Handoff.notification). When
    // you move the mouse it "settles": no new effects; the current one plays out at
    // settleSpeed and pauses on the full logo — behind the lock screen, if macOS keeps
    // it there — and it announces the moment settling began. The Applarchy wallpaper,
    // in hold mode, computes the same timeline when the desktop comes back (the
    // engine is deterministic for a seed): it carries on settling from the matching
    // frame or, if that's over, shows the paused logo. So screensaver → desktop and
    // screensaver → lock screen → desktop end the same way.

    static let settleSpeed = 6.0

    struct Handoff: Equatable {
        /// This build's handoff name, from its Info.plist (scripts/flavor.sh writes the same
        /// one into the app and its screensaver), so a DEV screensaver only talks to the
        /// DEV app and a released one to the released app.
        static let id = Bundle(for: ApplarchySaverView.self).object(forInfoDictionaryKey: "ApplarchyHandoffID") as? String
            ?? "com.applarchy.handoff"
        static let notification = Notification.Name(id)
        var command: String
        var seed: UInt64
        var startedAt: Date
        var size: CGSize
        /// When the screensaver began settling (the mouse moved), if it has.
        var settleAt: Date?

        /// Engine frame (120 per second, settleSpeed times faster once settling) at `t`.
        func frame(at t: Date) -> Int {
            let elapsed = min(t.timeIntervalSince(startedAt), 3600)
            guard let settleAt, t > settleAt else { return Int(max(0, elapsed) * 120) }
            let before = max(0, settleAt.timeIntervalSince(startedAt)) * 120
            return Int(before + min(t.timeIntervalSince(settleAt), 3600) * 120 * ApplarchySaverView.settleSpeed)
        }

        /// The named pasteboard a screen's screensaver leaves its latest announcement on
        /// (one per screen size). The app reads it when the desktop comes back; unlike a
        /// distributed notification, that doesn't depend on delivery at the moment it's sent.
        static func pasteboard(for size: CGSize) -> NSPasteboard {
            NSPasteboard(name: NSPasteboard.Name("\(id).\(Int(size.width))x\(Int(size.height))"))
        }

        /// Distributed-notification payload: sandboxed senders may only pass a string.
        var payload: String {
            "\(seed)|\(startedAt.timeIntervalSince1970)|\(Int(size.width))x\(Int(size.height))|\(settleAt?.timeIntervalSince1970 ?? 0)|\(command)"
        }

        init(command: String, seed: UInt64, startedAt: Date, size: CGSize, settleAt: Date? = nil) {
            self.command = command; self.seed = seed; self.startedAt = startedAt; self.size = size; self.settleAt = settleAt
        }

        init?(payload: String) {
            let parts = payload.split(separator: "|", maxSplits: 4).map(String.init)
            guard parts.count == 5, let seed = UInt64(parts[0]), let t = Double(parts[1]), let settle = Double(parts[3]) else { return nil }
            let wh = parts[2].split(separator: "x").compactMap { Double($0) }
            guard wh.count == 2 else { return nil }
            self.init(command: parts[4], seed: seed, startedAt: Date(timeIntervalSince1970: t),
                      size: CGSize(width: wh[0], height: wh[1]), settleAt: settle > 0 ? Date(timeIntervalSince1970: settle) : nil)
        }
    }

    /// Screensaver: keep playing through the lock screen and announce each effect.
    var smoothTransition = false
    /// Wallpaper: play `handoff` (or settle at once) and keep the last frame, instead of cycling.
    var holdsWhenDone = false
    var handoff: Handoff?
    private var holding = false
    /// Playing out the current effect at settleSpeed, then pausing.
    private var settling = false
    /// The effect the screensaver is playing, as announced.
    private var announced: Handoff?
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
    private var engineFramesPerTick: Int {
        max(1, Int((120 * animationTimeInterval * (settling ? Self.settleSpeed : 1)).rounded()))
    }
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
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(didStart),
            name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
    }

    /// macOS reuses a running screensaver instance (e.g. starting it again on the lock
    /// screen) without calling startAnimation, so an instance that settled on the logo
    /// last time would stay frozen. Start it animating again.
    @objc private func didStart(_ note: Notification) {
        guard !isPreview, settling || holding else { return }
        os_log("didstart: resuming from the settled logo", log: Self.log, type: .default)
        settling = false
        holding = false
        holdRemaining = 0
        startEffect()
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
        settling = false
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
        if smoothTransition && !isPreview {
            // The mouse moved: play out the current effect quickly, pause on the logo,
            // and tell the desktop when settling began.
            guard !settling else { return }
            settling = true
            if holdRemaining > 0 { holdRemaining = 0; holding = true }     // between effects: already settled
            if var h = announced, !holding {
                h.settleAt = Date()
                announce(h)
            }
            return
        }
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
        // Font size 18 on a 1512 pt wide screen (Omarchy's screensaver size), scaled to the view.
        let size = max(3, bounds.width / 84)
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
        holding = false
        let text = logo
        let height = Int32(rows + logoLayout().extra)   // rows past the screen are never drawn
        if holdsWhenDone { resumeHandoff(text: text, height: height); return }
        let seed = UInt64.random(in: 1...UInt64.max)
        // Fall back to a random pick if a named effect can't be built.
        let name = theme.command(for: nextEffectName())
        saver = text.withCString { t in name.withCString { ttfx_saver_new_named(t, Int32(cols), height, seed, $0) } }
            ?? text.withCString { ttfx_saver_new($0, Int32(cols), height, seed) }
        os_log("effect %{public}@ %{public}@", log: Self.log, type: .default, name, saver == nil ? "FAILED" : "ok")
        engineFrames = 0
        holdRemaining = 0
        if smoothTransition, !isPreview, saver != nil {
            let h = Handoff(command: name, seed: seed, startedAt: Date(), size: bounds.size)
            announced = h
            announce(h)
        }
    }

    /// Tell the Applarchy wallpaper what's playing: a distributed notification and the
    /// screen's named pasteboard (whichever reaches it).
    private func announce(_ h: Handoff) {
        DistributedNotificationCenter.default().postNotificationName(Handoff.notification, object: h.payload, userInfo: nil, deliverImmediately: true)
        let board = Handoff.pasteboard(for: h.size)
        board.clearContents()
        let ok = board.setString(h.payload, forType: .string)
        os_log("announced %{public}@%{public}@ for %{public}dx%{public}d (pasteboard %{public}@)", log: Self.log, type: .default,
               String(h.command.split(separator: " ").first { !$0.hasPrefix("-") && !$0.allSatisfy(\.isHexDigit) } ?? ""),
               h.settleAt == nil ? "" : " settling", Int(h.size.width), Int(h.size.height), ok ? "ok" : "FAILED")
    }

    /// Hold mode: rebuild the handed-off effect (or a quick wipe when there's none),
    /// fast-forward to where the screensaver would be now, and either carry on from
    /// there or, if it has already finished, show its last frame and hold it.
    private func resumeHandoff(text: String, height: Int32) {
        // Kept after use: a later restart (e.g. the desktop is uncovered) settles on the same last frame.
        let h = handoff ?? Handoff(command: theme.command(for: "wipe"), seed: 1, startedAt: .distantPast, size: bounds.size)
        saver = text.withCString { t in h.command.withCString { ttfx_saver_new_named(t, Int32(cols), height, h.seed, $0) } }
        guard let saver else { return }
        let target = h.frame(at: Date())
        settling = h.settleAt != nil                                   // keep settling at the same speed
        var frame: UnsafePointer<UInt8>?, len = 0, n = 0
        while n < max(target, 1), let next = ttfx_saver_next(saver, &len) { frame = next; n += 1 }
        engineFrames = n
        if let frame {
            parse(UnsafeBufferPointer(start: frame, count: len))
            previous = cells
            invalidateAll()
        }
        if n < max(target, 1) {          // already finished: hold its last frame
            endEffect()
            holding = true
        }
        os_log("handoff %{public}@ at frame %{public}d%{public}@", log: Self.log, type: .default, h.command, n, holding ? " (finished)" : "")
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
        if holding { return }
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
            if holdsWhenDone || settling { holding = true; return }
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

    /// The current picture, in bitmap mode (for rendering stills, e.g. the lock-screen picture).
    func snapshotImage() -> CGImage? { bitmap?.makeImage() }

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

    /// Redraw only the cells that differ from the last frame, a run per row
    /// (padded a cell each side for glyphs that overhang their cell).
    private func invalidateChangedCells() {
        guard previous.count == cells.count else { invalidateAll(); return }
        let o = gridOrigin
        cells.withUnsafeBufferPointer { now in
            previous.withUnsafeBufferPointer { old in
                for r in 0..<rows {
                    let base = r * cols
                    var first = -1, last = -1
                    for c in 0..<cols where now[base + c] != old[base + c] {
                        if first < 0 { first = c }
                        last = c
                    }
                    guard first >= 0 else { continue }
                    let c0 = max(0, first - 1), c1 = min(cols - 1, last + 1)
                    invalidate(NSRect(x: o.x + CGFloat(c0) * cellW - 1, y: o.y + CGFloat(r) * cellH - 1,
                                           width: CGFloat(c1 - c0 + 1) * cellW + 2, height: cellH + 2))
                }
            }
        }
    }

    private func parse(_ bytes: UnsafeBufferPointer<UInt8>) {
        var row = 0, col = 0
        var fg: UInt32 = 0xC0C0C0, bg: UInt32 = 0xFFFF_FFFF
        var i = 0
        let n = bytes.count
        for k in cells.indices { cells[k] = Cell() }
        while i < n {
            let b = bytes[i]
            if b == 0x1B {
                i += 1
                guard i < n else { break }
                if bytes[i] != UInt8(ascii: "[") { i += 1; continue }   // ESC 7 / ESC 8
                i += 1
                var params: [Int] = []
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
        if showsClock && clockVisible {
            var style = clockStyle
            style.color = theme.foreground
            PixelClock.draw(in: bounds, top: round((logoTop - PixelClock.height(in: bounds, style: clockStyle)) / 2), style: style, ctx)
        }
    }

    private func color(_ rgb: UInt32) -> CGColor {
        CGColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
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
        return glyphs[0] == 0 ? nil : (f, glyphs[0])
    }

    // MARK: logo

    private var logoCentre: CGFloat {
        // Below the clock: the clock block plus 38 pt of margin (on a 982 pt screen).
        let top = logoRegionTop.map { bounds.height * $0 }
            ?? (showsClock ? 38 * bounds.height / 982 + PixelClock.height(in: bounds, style: clockStyle) : 0)
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
        if let smooth = config["smoothTransition"] as? Bool { smoothTransition = smooth }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
