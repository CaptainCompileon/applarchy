import Foundation

/// The 37 ttfx effects, with their descriptions from `ttfx --help`.
struct EffectInfo: Identifiable, Hashable {
    let id: String
    let summary: String
    var title: String {
        switch id {
        case "binarypath": "Binary Path"
        case "bouncyballs": "Bouncy Balls"
        case "colorshift": "Color Shift"
        case "errorcorrect": "Error Correct"
        case "laseretch": "Laser Etch"
        case "middleout": "Middle Out"
        case "orbittingvolley": "Orbiting Volley"
        case "randomsequence": "Random Sequence"
        case "synthgrid": "Synth Grid"
        case "vhstape": "VHS Tape"
        default: id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}

enum Catalog {
    static let effects: [EffectInfo] = [
        .init(id: "beams", summary: "Beams travel over the canvas, illuminating the characters behind them"),
        .init(id: "binarypath", summary: "Binary representations of each character move towards their home"),
        .init(id: "blackhole", summary: "Characters are consumed by a black hole and explode outwards"),
        .init(id: "bouncyballs", summary: "Characters are bouncy balls falling from the top of the canvas"),
        .init(id: "bubbles", summary: "Characters are formed into bubbles that float down and pop"),
        .init(id: "burn", summary: "Burns vertically in the canvas"),
        .init(id: "colorshift", summary: "A gradient that shifts colors across the terminal"),
        .init(id: "crumble", summary: "Characters lose color and crumble into dust, are vacuumed up, and reformed"),
        .init(id: "decrypt", summary: "A movie-style decryption effect"),
        .init(id: "errorcorrect", summary: "Some characters start in the wrong position and are corrected in sequence"),
        .init(id: "expand", summary: "Expands the text from a single point"),
        .init(id: "fireworks", summary: "Characters launch and explode like fireworks and fall into place"),
        .init(id: "highlight", summary: "A specular highlight runs across the text"),
        .init(id: "laseretch", summary: "A laser etches characters onto the terminal"),
        .init(id: "matrix", summary: "Matrix digital rain"),
        .init(id: "middleout", summary: "Text expands in a single row or column in the middle, then out"),
        .init(id: "orbittingvolley", summary: "Four launchers orbit the canvas, firing volleys of characters inward"),
        .init(id: "overflow", summary: "Text overflows and scrolls in a random order until it appears ordered"),
        .init(id: "pour", summary: "Pours the characters into position from a direction"),
        .init(id: "print", summary: "Lines are printed one at a time following a print head"),
        .init(id: "rain", summary: "Rains characters from the top of the canvas"),
        .init(id: "randomsequence", summary: "Prints the text in a random sequence"),
        .init(id: "rings", summary: "Characters are dispersed and form into spinning rings"),
        .init(id: "scattered", summary: "Text is scattered across the canvas and moves into position"),
        .init(id: "slice", summary: "Slices the text in half and slides it into place from opposite directions"),
        .init(id: "slide", summary: "Slides characters into view from outside the canvas"),
        .init(id: "smoke", summary: "Smoke floods the canvas, colorizing any characters it crosses"),
        .init(id: "spotlights", summary: "Spotlights search the text, converge in the center and expand"),
        .init(id: "spray", summary: "Draws the characters spawning at varying rates from a single point"),
        .init(id: "swarm", summary: "Characters are grouped into swarms that move around before settling"),
        .init(id: "sweep", summary: "Sweeps across the canvas to reveal the text, then sweeps back to color it"),
        .init(id: "synthgrid", summary: "A grid fills with characters dissolving into the final text"),
        .init(id: "thunderstorm", summary: "A thunderstorm, with rain and lightning striking the text"),
        .init(id: "unstable", summary: "Characters spawn jumbled, explode to the edges, then reassemble"),
        .init(id: "vhstape", summary: "Lines glitch left and right and lose detail like an old VHS tape"),
        .init(id: "waves", summary: "Waves travel across the canvas, leaving the characters behind"),
        .init(id: "wipe", summary: "Wipes the text across the canvas to reveal it"),
    ]
    static let allIDs = effects.map(\.id)
}
