// Generates studio/AppIcon.icns: a pixel-art storm cloud in Omarchy's gradient
// on a black macOS icon squircle. Run: swift scripts/make-icon.swift
import AppKit

let art = [
    "........................",
    "........................",
    "........................",
    "........................",
    "..........#####.........",
    "........########........",
    "........#########.......",
    ".......##########.......",
    ".......############.....",
    ".....################...",
    "....#################...",
    "...###################..",
    "...###################..",
    "...###################..",
    "...###################..",
    "...##########**#######..",
    "...#########**#######...",
    "...........**...........",
    "..........*****.........",
    "............**..........",
    "...........**...........",
    "..........**............",
    ".........**.............",
    ".........*..............",
]

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let top = color(0x00D1FF), bottom = color(0x8A008A)

func render(_ size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024
    // macOS icon grid: 824pt body, 100pt margin, ~185pt corner radius
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0x17171C), ending: color(0x050507))!.draw(in: shape, angle: -90)
    color(0xFFFFFF).withAlphaComponent(0.08).setStroke(); shape.lineWidth = max(1, 4 * s); shape.stroke()
    // pixel art, 24x24, 24pt per pixel, nudged up so the drawing is optically centred
    let n = art.count
    let px = 24 * s
    let ox = (CGFloat(size) - px * CGFloat(n)) / 2, oy = (CGFloat(size) - px * CGFloat(n)) / 2 + 20 * s
    let cloudRows = art.enumerated().filter { $0.element.contains("#") }.map(\.offset)
    for (r, row) in art.enumerated() {
        for (c, ch) in row.enumerated() where ch != "." {
            if ch == "*" { color(0xFFFFFF).setFill() }
            else {
                let t = CGFloat(r - cloudRows.first!) / CGFloat(max(1, cloudRows.last! - cloudRows.first!))
                (top.blended(withFraction: t, of: bottom) ?? top).setFill()
            }
            NSRect(x: ox + CGFloat(c) * px, y: oy + CGFloat(n - 1 - r) * px, width: px, height: px).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("docs/icon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("studio/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote studio/AppIcon.icns and docs/icon.png" : "iconutil failed")
