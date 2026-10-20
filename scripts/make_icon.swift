// Renders the Paltsuun app icon into Paltsuun/Assets.xcassets/AppIcon.appiconset and the
// menu bar icon into Paltsuun/Assets.xcassets/MenuBarIcon.imageset.
//
// Usage: swift scripts/make_icon.swift

import AppKit
import CoreGraphics

let canvas: CGFloat = 1024

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// macOS style continuous-corner rounded square (superellipse).
func squirclePath(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let cx = rect.midX, cy = rect.midY
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * copysign(pow(abs(c), 2 / n), c)
        let y = cy + b * copysign(pow(abs(s), 2 / n), s)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func drawIcon(_ ctx: CGContext) {
    let s = canvas
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squirclePath(in: body)
    let center = CGPoint(x: s / 2, y: s / 2 - 6)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(rgb(0.08, 0.10, 0.16))
    ctx.fillPath()
    ctx.restoreGState()

    // Tile background: deep night blue.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                        colors: [rgb(0.17, 0.21, 0.33), rgb(0.06, 0.07, 0.12)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: s / 2, y: body.maxY), end: CGPoint(x: s / 2, y: body.minY), options: [])

    // Soft glow behind the ring.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [rgb(0.30, 0.85, 0.55, 0.20), rgb(0.30, 0.85, 0.55, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 400, options: [])
    ctx.restoreGState()

    // Countdown ring.
    let radius: CGFloat = 268
    let width: CGFloat = 86

    // Track.
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.10))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()

    // Remaining time arc, running clockwise from 12 o'clock, colored with the
    // app's urgency colors: green, amber, orange and finally red.
    let top = CGFloat.pi / 2
    let sweep = CGFloat.pi * 2 * 0.72
    let end = top - sweep
    let stops: [(t: CGFloat, color: (CGFloat, CGFloat, CGFloat))] = [
        (0.00, (0.20, 0.78, 0.45)),
        (0.30, (0.20, 0.78, 0.45)),
        (0.55, (0.96, 0.66, 0.08)),
        (0.78, (0.93, 0.40, 0.10)),
        (1.00, (0.86, 0.16, 0.24)),
    ]
    func color(at t: CGFloat) -> CGColor {
        let i = max(1, stops.firstIndex { $0.t >= t } ?? stops.count - 1)
        let (lo, hi) = (stops[i - 1], stops[i])
        let f = (t - lo.t) / (hi.t - lo.t)
        return rgb(lo.color.0 + (hi.color.0 - lo.color.0) * f,
                   lo.color.1 + (hi.color.1 - lo.color.1) * f,
                   lo.color.2 + (hi.color.2 - lo.color.2) * f)
    }
    func point(at angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    // Round caps at both ends.
    for (angle, t) in [(top, CGFloat(0)), (end, CGFloat(1))] {
        let p = point(at: angle)
        ctx.setFillColor(color(at: t))
        ctx.fillEllipse(in: CGRect(x: p.x - width / 2, y: p.y - width / 2, width: width, height: width))
    }
    // The arc itself, as many short segments that overlap slightly to hide seams.
    let segments = 600
    ctx.setLineCap(.butt)
    for i in 0..<segments {
        let t0 = CGFloat(i) / CGFloat(segments)
        let t1 = CGFloat(i + 1) / CGFloat(segments)
        ctx.setStrokeColor(color(at: (t0 + t1) / 2))
        ctx.addArc(center: center, radius: radius, startAngle: top - sweep * t0 + 0.002,
                   endAngle: top - sweep * t1 - 0.002, clockwise: true)
        ctx.strokePath()
    }

    // Clock hands, pointing at the start of the meeting.
    ctx.setStrokeColor(rgb(1, 1, 1))
    ctx.setLineCap(.round)
    ctx.setLineWidth(58)
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x, y: center.y + 150))
    ctx.strokePath()
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + 102, y: center.y - 70))
    ctx.strokePath()
    ctx.setFillColor(rgb(1, 1, 1))
    ctx.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
}

/// Monochrome version of the app icon for the menu bar: the countdown ring and clock hands,
/// drawn in black so macOS can tint it as a template image.
func drawMenuBarIcon(_ ctx: CGContext) {
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let point = canvas / 18

    ctx.setStrokeColor(rgb(0, 0, 0))
    ctx.setLineCap(.round)

    // Countdown ring with the same gap as in the app icon.
    let top = CGFloat.pi / 2
    ctx.setLineWidth(1.9 * point)
    ctx.addArc(center: center, radius: 6.55 * point, startAngle: top,
               endAngle: top - CGFloat.pi * 2 * 0.72, clockwise: true)
    ctx.strokePath()

    // Clock hands.
    ctx.setLineWidth(1.6 * point)
    ctx.move(to: CGPoint(x: center.x, y: center.y + 3.7 * point))
    ctx.addLine(to: center)
    ctx.addLine(to: CGPoint(x: center.x + 2.6 * point, y: center.y - 1.8 * point))
    ctx.strokePath()
}

func render(size: Int, draw: (CGContext) -> Void = drawIcon) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let assets = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Paltsuun/Assets.xcassets")

func writeContents(_ contents: [String: Any], to dir: URL) {
    let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try! json.write(to: dir.appendingPathComponent("Contents.json"))
}

let appIcon = assets.appendingPathComponent("AppIcon.appiconset")
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(size: points * scale).write(to: appIcon.appendingPathComponent(name))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
writeContents(["images": images, "info": ["author": "xcode", "version": 1]], to: appIcon)

let menuBarIcon = assets.appendingPathComponent("MenuBarIcon.imageset")
try! FileManager.default.createDirectory(at: menuBarIcon, withIntermediateDirectories: true)
var menuBarImages: [[String: String]] = []
for scale in [1, 2] {
    let name = "menubar\(scale == 2 ? "@2x" : "").png"
    try! render(size: 18 * scale, draw: drawMenuBarIcon).write(to: menuBarIcon.appendingPathComponent(name))
    menuBarImages.append(["idiom": "universal", "scale": "\(scale)x", "filename": name])
}
writeContents(["images": menuBarImages, "info": ["author": "xcode", "version": 1],
               "properties": ["template-rendering-intent": "template"]], to: menuBarIcon)

print("Wrote icons to \(assets.path)")
