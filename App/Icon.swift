// Draws the app icon as a 1024×1024 PNG. Run via `mise run icon`, which also builds App/AppIcon.icns.
// Usage: swift App/Icon.swift <output.png>

import AppKit

let canvas: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// MARK: Tile (Apple's macOS icon grid: 824pt rounded square, 100pt inset)

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35).cgColor)
rgb(40, 60, 130).setFill()
tilePath.fill()
ctx.restoreGState()

ctx.saveGState()
tilePath.addClip()
// NSGradient at 90°: the first color is at the bottom.
NSGradient(colors: [rgb(28, 40, 104), rgb(62, 108, 214), rgb(118, 170, 248)])!.draw(in: tile, angle: 90)
ctx.restoreGState()

// MARK: Photo cards

struct Scene {
    var sky: [NSColor]       // bottom → top
    var sun: NSColor
    var sunAt: CGPoint       // relative to the photo
    var far: NSColor
    var near: NSColor
}

let day = Scene(
    sky: [rgb(196, 232, 255), rgb(92, 170, 240)],
    sun: rgb(255, 246, 200),
    sunAt: CGPoint(x: 0.28, y: 0.68),
    far: rgb(120, 190, 150),
    near: rgb(52, 140, 96)
)

let sunset = Scene(
    sky: [rgb(255, 170, 110), rgb(236, 112, 140), rgb(120, 84, 190)],
    sun: rgb(255, 214, 120),
    sunAt: CGPoint(x: 0.68, y: 0.50),
    far: rgb(150, 92, 160),
    near: rgb(70, 48, 112)
)

func polygon(_ points: [(CGFloat, CGFloat)], in rect: CGRect) -> NSBezierPath {
    let path = NSBezierPath()
    for (i, p) in points.enumerated() {
        let pt = CGPoint(x: rect.minX + p.0 * rect.width, y: rect.minY + p.1 * rect.height)
        i == 0 ? path.move(to: pt) : path.line(to: pt)
    }
    path.close()
    return path
}

func card(center: CGPoint, degrees: CGFloat, scene: Scene) {
    let width: CGFloat = 560, height: CGFloat = 430, border: CGFloat = 26

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)

    let outer = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 30, 0.45).cgColor)
    rgb(250, 250, 252).setFill()
    NSBezierPath(roundedRect: outer, xRadius: 28, yRadius: 28).fill()
    ctx.restoreGState()

    let photo = outer.insetBy(dx: border, dy: border)
    ctx.saveGState()
    NSBezierPath(roundedRect: photo, xRadius: 12, yRadius: 12).addClip()

    NSGradient(colors: scene.sky)!.draw(in: photo, angle: 90)

    let r: CGFloat = 50
    let sun = CGPoint(x: photo.minX + scene.sunAt.x * photo.width, y: photo.minY + scene.sunAt.y * photo.height)
    scene.sun.withAlphaComponent(0.35).setFill()
    NSBezierPath(ovalIn: CGRect(x: sun.x - r * 1.6, y: sun.y - r * 1.6, width: r * 3.2, height: r * 3.2)).fill()
    scene.sun.setFill()
    NSBezierPath(ovalIn: CGRect(x: sun.x - r, y: sun.y - r, width: r * 2, height: r * 2)).fill()

    scene.far.setFill()
    polygon([(0, 0), (0, 0.36), (0.22, 0.60), (0.42, 0.42), (0.60, 0.62), (0.84, 0.38), (1, 0.50), (1, 0)], in: photo).fill()
    scene.near.setFill()
    polygon([(0, 0), (0, 0.22), (0.18, 0.40), (0.36, 0.26), (0.56, 0.46), (0.78, 0.20), (1, 0.32), (1, 0)], in: photo).fill()

    ctx.restoreGState()
    ctx.restoreGState()
}

card(center: CGPoint(x: 492, y: 556), degrees: 9, scene: day)
card(center: CGPoint(x: 532, y: 462), degrees: -6, scene: sunset)

// MARK: Write

let out = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
