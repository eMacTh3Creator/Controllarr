#!/usr/bin/env swift
//
// Controllarr — icon generator
//
// Renders a 1024×1024 PNG of the Controllarr app icon using Core Graphics.
// The design: a macOS-style squircle with a blue→dark-blue vertical gradient
// background, a subtle top highlight, and two interlocked arrows — one
// pointing down (download, accent blue) and one pointing up (upload,
// seed green) — meant to echo the `arrow.up.arrow.down.circle` glyph
// used in the menu bar, but bolder and more recognisable at icon sizes.
//
// Usage: swift Scripts/make-icon.swift <output.png>
//

import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <output.png>\n".data(using: .utf8)!)
    exit(1)
}
let outputPath = args[1]

let size = CGSize(width: 1024, height: 1024)
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: Int(size.width),
    height: Int(size.height),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write("failed to create bitmap context\n".data(using: .utf8)!)
    exit(1)
}

// MARK: Squircle background with gradient

let padding: CGFloat = 40
let rect = CGRect(
    x: padding,
    y: padding,
    width: size.width - padding * 2,
    height: size.height - padding * 2
)
let cornerRadius: CGFloat = 224 // close to macOS Big Sur+ icon shape

let squircle = CGPath(
    roundedRect: rect,
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// Top-to-bottom gradient: accent blue → deep navy
let bgColors = [
    CGColor(red: 0.38, green: 0.66, blue: 1.00, alpha: 1.0), // top
    CGColor(red: 0.11, green: 0.20, blue: 0.42, alpha: 1.0), // middle
    CGColor(red: 0.04, green: 0.07, blue: 0.18, alpha: 1.0), // bottom
]
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: bgColors as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size.height),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// Subtle top highlight — a soft white radial bloom near the top edge
let highlightColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
]
let highlight = CGGradient(
    colorsSpace: colorSpace,
    colors: highlightColors as CFArray,
    locations: [0, 1]
)!
ctx.drawRadialGradient(
    highlight,
    startCenter: CGPoint(x: size.width / 2, y: size.height - 120),
    startRadius: 0,
    endCenter: CGPoint(x: size.width / 2, y: size.height - 120),
    endRadius: size.width * 0.55,
    options: []
)

ctx.restoreGState()

// Inner stroke for a crisper edge
ctx.saveGState()
ctx.addPath(squircle)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

// MARK: Arrows

/// Draws a thick arrow centred on `center`, pointing up if `direction == 1`,
/// or down if `direction == -1`. The shape has a rectangular shaft and a
/// triangular head, smoothed by the context's line join setting.
func drawArrow(
    center: CGPoint,
    direction: CGFloat,
    color: CGColor,
    shadow: CGColor
) {
    let shaftWidth: CGFloat = 150
    let headWidth: CGFloat = 340
    let totalHeight: CGFloat = 560
    let headHeight: CGFloat = 210

    let halfH = totalHeight / 2
    let tailY = center.y - direction * halfH
    let tipY = center.y + direction * halfH
    let headBaseY = tipY - direction * headHeight

    let path = CGMutablePath()
    path.move(to: CGPoint(x: center.x - shaftWidth / 2, y: tailY))
    path.addLine(to: CGPoint(x: center.x + shaftWidth / 2, y: tailY))
    path.addLine(to: CGPoint(x: center.x + shaftWidth / 2, y: headBaseY))
    path.addLine(to: CGPoint(x: center.x + headWidth / 2, y: headBaseY))
    path.addLine(to: CGPoint(x: center.x, y: tipY))
    path.addLine(to: CGPoint(x: center.x - headWidth / 2, y: headBaseY))
    path.addLine(to: CGPoint(x: center.x - shaftWidth / 2, y: headBaseY))
    path.closeSubpath()

    // Drop shadow for a little lift off the gradient background
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -12),
        blur: 32,
        color: shadow
    )
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

// Download arrow (left, pointing down) — accent blue
drawArrow(
    center: CGPoint(x: size.width / 2 - 180, y: size.height / 2),
    direction: -1,
    color: CGColor(red: 0.55, green: 0.78, blue: 1.00, alpha: 1.0),
    shadow: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
)

// Upload arrow (right, pointing up) — seed green
drawArrow(
    center: CGPoint(x: size.width / 2 + 180, y: size.height / 2),
    direction: 1,
    color: CGColor(red: 0.50, green: 0.92, blue: 0.62, alpha: 1.0),
    shadow: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55)
)

// MARK: Write PNG

guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write("failed to finalize image\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try pngData.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath) (\(pngData.count) bytes)")
