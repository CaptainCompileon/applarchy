import AppKit

/// A blocky 5x7 pixel-font clock and date, drawn over the top of the screensaver
/// to match the half-block logo (in place of the system's large lock-screen clock).
/// How the clock looks: 12/24-hour ("auto" follows the system), with or without
/// the date, small or large, in the theme's foreground colour.
struct ClockStyle: Equatable {
    var hourCycle = "auto"          // "auto" | "12" | "24"
    var showDate = true
    var large = false
    var color: UInt32 = 0xF0F0F0
}

/// How much to scale the layout (text grid, logo, clock) for a screen: 1 on a
/// 1512 x 982 pt screen (Omarchy's screensaver size). The smaller of the two ratios,
/// so it looks the same on ultrawide and portrait screens, just with more room
/// around it, instead of overflowing the short side.
func layoutScale(_ bounds: CGRect) -> CGFloat {
    min(bounds.width / 1512, bounds.height / 982)
}

enum PixelClock {
    // Sizes on a 1512 x 982 pt screen; scaled to the view.
    private static func metrics(_ style: ClockStyle, _ bounds: CGRect) -> (date: CGFloat, time: CGFloat, gap: CGFloat) {
        let s = layoutScale(bounds)
        let date: CGFloat = style.large ? 5 : 4, time: CGFloat = style.large ? 18 : 13, gap: CGFloat = style.large ? 16 : 14
        return (max(1, floor(date * s)), max(1, floor(time * s)), round(gap * s))
    }

    private static let autoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jmm")  // honours the system 12/24-hour setting
        return f
    }()

    private static func fixedFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let twelve = fixedFormatter("h:mm a")
    private static let twentyFour = fixedFormatter("HH:mm")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()

    static func timeString(_ style: ClockStyle = ClockStyle(), _ date: Date = Date()) -> String {
        let f = style.hourCycle == "12" ? twelve : style.hourCycle == "24" ? twentyFour : autoFormatter
        return f.string(from: date).uppercased()
    }

    /// Height of the date + time block.
    static func height(in bounds: CGRect, style: ClockStyle = ClockStyle()) -> CGFloat {
        let m = metrics(style, bounds)
        return (style.showDate ? 7 * m.date + m.gap : 0) + 7 * m.time
    }

    /// The date line, formatted at most once a second (the clock may be drawn many times a frame).
    private static var dateCache: (second: Int, text: String)?
    private static func dateString(_ date: Date) -> String {
        let second = Int(date.timeIntervalSinceReferenceDate)
        if let c = dateCache, c.second == second { return c.text }
        let text = dateFormatter.string(from: date).folding(options: .diacriticInsensitive, locale: nil).uppercased()
        dateCache = (second, text)
        return text
    }

    static func draw(in bounds: CGRect, top: CGFloat, style: ClockStyle = ClockStyle(), _ ctx: CGContext) {
        let now = Date()
        let m = metrics(style, bounds)
        let c = style.color
        let r = CGFloat(c >> 16 & 0xFF) / 255, g = CGFloat(c >> 8 & 0xFF) / 255, b = CGFloat(c & 0xFF) / 255
        var y = top
        if style.showDate {
            let date = dateString(now)
            ctx.setFillColor(CGColor(red: r * 0.66, green: g * 0.66, blue: b * 0.66, alpha: 0.92))
            drawText(date, pixel: m.date, centreX: bounds.midX, top: y, ctx)
            y += 7 * m.date + m.gap
        }
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 0.95))
        drawText(timeString(style, now), pixel: m.time, centreX: bounds.midX, top: y, ctx)
    }

    private static func drawText(_ text: String, pixel p: CGFloat, centreX: CGFloat, top: CGFloat, _ ctx: CGContext) {
        let glyphs = text.map { font[$0] ?? font[" "]! }
        let widthPx = glyphs.reduce(0) { $0 + $1[0].count + 1 } - 1
        var x = round(centreX - CGFloat(widthPx) * p / 2)
        for g in glyphs {
            for (r, row) in g.enumerated() {
                for (c, ch) in row.enumerated() where ch == "#" {
                    ctx.fill(CGRect(x: x + CGFloat(c) * p, y: top + CGFloat(r) * p, width: p, height: p))
                }
            }
            x += CGFloat(g[0].count + 1) * p
        }
    }

    private static let font: [Character: [String]] = {
        var f: [Character: [String]] = [
            " ": ["   ", "   ", "   ", "   ", "   ", "   ", "   "],
            ":": [" ", " ", "#", " ", "#", " ", " "],
            ".": [" ", " ", " ", " ", " ", " ", "#"],
            ",": ["  ", "  ", "  ", "  ", "  ", " #", "# "],
            "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
            "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
            "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
            "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
            "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
            "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
            "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
            "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
            "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
            "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
            "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
            "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
            "C": [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
            "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
            "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
            "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
            "G": [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
            "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
            "I": [" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
            "J": ["  ###", "   # ", "   # ", "   # ", "   # ", "#  # ", " ##  "],
            "K": ["#   #", "#  # ", "# #  ", "##   ", "# #  ", "#  # ", "#   #"],
            "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
            "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
            "N": ["#   #", "#   #", "##  #", "# # #", "#  ##", "#   #", "#   #"],
            "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
            "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
            "Q": [" ### ", "#   #", "#   #", "#   #", "# # #", "#  # ", " ## #"],
            "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
            "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
            "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
            "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
            "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
            "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "# # #", " # # "],
            "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
            "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
            "Z": ["#####", "    #", "   # ", "  #  ", " #   ", "#    ", "#####"],
        ]
        f["\u{202F}"] = f[" "]  // narrow no-break space (before AM/PM)
        f["\u{00A0}"] = f[" "]
        return f
    }()
}
