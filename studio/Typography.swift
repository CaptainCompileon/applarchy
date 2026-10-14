import CoreText
import SwiftUI

/// One typeface for the whole app: Departure Mono by Helena Zhang (SIL OFL 1.1,
/// bundled in Resources), a pixel monospace drawn on an 11 px grid. Only sizes on
/// that grid are used (11, 16.5 and 22 pt, i.e. 22, 33 and 44 px on Retina) so every
/// stem lands on whole pixels. It has a single weight: hierarchy comes from size,
/// capitals and colour, never bold.
enum Pixel {
    static let postScriptName = "DepartureMono-Regular"

    static let body = font(11)        // everything by default
    static let title = font(16.5)     // section titles, big buttons
    static let display = font(22)     // tutorial headings

    static func font(_ size: CGFloat) -> Font { .custom(postScriptName, fixedSize: size) }

    /// Make the bundled font available to this process. Call before any view is built.
    static func register() {
        guard let url = Bundle.main.url(forResource: postScriptName, withExtension: "otf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}
