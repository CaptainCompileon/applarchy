import AppKit

/// A blocky 5x7 pixel-font clock and date, drawn over the top of the screensaver
/// to match the half-block logo (in place of the system's large lock-screen clock).
enum PixelClock {
    // Sizes on a 982 pt tall screen; scaled to the view.
    private static let datePixel: CGFloat = 4
    private static let timePixel: CGFloat = 13
    private static let gap: CGFloat = 14

    private static let timeColor = CGColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 0.92)
    private static let dateColor = CGColor(red: 0.62, green: 0.62, blue: 0.62, alpha: 0.92)

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jmm")  // honours the 12/24-hour setting
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return f
    }()

    static func timeString(_ date: Date = Date()) -> String {
        timeFormatter.string(from: date).uppercased()
    }

    /// Height of the date + time block.
    static func height(in bounds: CGRect) -> CGFloat {
        let s = bounds.height / 982
        let dp = max(1, floor(datePixel * s)), tp = max(1, floor(timePixel * s))
        return 7 * dp + round(gap * s) + 7 * tp
    }

    static func draw(in bounds: CGRect, top: CGFloat, _ ctx: CGContext) {
        let now = Date()
        let s = bounds.height / 982
        let dp = max(1, floor(datePixel * s)), tp = max(1, floor(timePixel * s))
        let date = dateFormatter.string(from: now)
            .folding(options: .diacriticInsensitive, locale: nil).uppercased()
        var y = top
        ctx.setFillColor(dateColor)
        drawText(date, pixel: dp, centreX: bounds.midX, top: y, ctx)
        y += 7 * dp + round(gap * s)
        ctx.setFillColor(timeColor)
        drawText(timeString(now), pixel: tp, centreX: bounds.midX, top: y, ctx)
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
