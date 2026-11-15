#!/usr/bin/env swift
// Generates Resources/AppIcon.icns: emerald squircle, white heart, pulse line.
// Usage: swift scripts/make-icon.swift   (run from the project root)
import AppKit
import Foundation

let canvas: CGFloat = 1024

func drawIcon(in ctx: CGContext) {
    // Apple macOS icon grid: 824pt body centred on a 1024 canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let radius: CGFloat = 185
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient body
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let colors = [
        NSColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1).cgColor,  // #34D399
        NSColor(red: 0.02, green: 0.47, blue: 0.34, alpha: 1).cgColor,  // #057857
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Soft top highlight
    let gloss = [NSColor.white.withAlphaComponent(0.22).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
    let glossGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gloss, locations: [0, 1])!
    ctx.drawLinearGradient(glossGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Heart (classic parametric curve)
    let heart = CGMutablePath()
    let scale: CGFloat = 17.5
    let cx: CGFloat = 512, cy: CGFloat = 548
    for i in 0...720 {
        let t = Double(i) / 720 * 2 * .pi
        let x = 16 * pow(sin(t), 3)
        let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        let p = CGPoint(x: cx + CGFloat(x) * scale, y: cy + CGFloat(y) * scale)
        if i == 0 { heart.move(to: p) } else { heart.addLine(to: p) }
    }
    heart.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(heart)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Pulse line across the heart
    let pulse = CGMutablePath()
    let points: [CGPoint] = [
        CGPoint(x: 285, y: 540), CGPoint(x: 400, y: 540), CGPoint(x: 440, y: 615),
        CGPoint(x: 492, y: 410), CGPoint(x: 546, y: 645), CGPoint(x: 588, y: 540),
        CGPoint(x: 739, y: 540),
    ]
    pulse.addLines(between: points)
    ctx.saveGState()
    ctx.addPath(heart)
    ctx.clip()
    ctx.addPath(pulse)
    ctx.setStrokeColor(NSColor(red: 0.02, green: 0.55, blue: 0.40, alpha: 1).cgColor)
    ctx.setLineWidth(38)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    drawIcon(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote Resources/AppIcon.icns and Resources/AppIcon.png")
