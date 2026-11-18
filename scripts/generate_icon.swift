import AppKit
import CoreGraphics
import Foundation

let size: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Failed to create CGContext")
}

// Clear transparent background
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// macOS icon squircle padding (~10% inset on each side)
let inset: CGFloat = 100
let iconRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let cornerRadius: CGFloat = 185

let bgPath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Subtle drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 36, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
ctx.addPath(bgPath)
ctx.setFillColor(CGColor(red: 0.08, green: 0.14, blue: 0.28, alpha: 1.0))
ctx.fillPath()
ctx.restoreGState()

// Clip to squircle and draw rich gradient
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()

let gradientColors = [
    CGColor(red: 0.11, green: 0.22, blue: 0.45, alpha: 1.0),
    CGColor(red: 0.06, green: 0.11, blue: 0.24, alpha: 1.0)
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: iconRect.maxY),
        end: CGPoint(x: size / 2, y: iconRect.minY),
        options: []
    )
}

// Subtle inner highlight border
ctx.addPath(bgPath)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// Draw 3 tiled workspace panes inside (2 on top, 1 wide on bottom — iconic & clear)
let innerPad: CGFloat = 175
let contentRect = CGRect(x: innerPad, y: innerPad, width: size - innerPad * 2, height: size - innerPad * 2)
let gap: CGFloat = 34
let paneRadius: CGFloat = 44

let topH = (contentRect.height - gap) * 0.52
let botH = (contentRect.height - gap) * 0.48
let halfW = (contentRect.width - gap) * 0.5

let topLeft = CGRect(x: contentRect.minX, y: contentRect.maxY - topH, width: halfW, height: topH)
let topRight = CGRect(x: contentRect.minX + halfW + gap, y: contentRect.maxY - topH, width: halfW, height: topH)
let bottomWide = CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: botH)

func drawPane(_ rect: CGRect, topColor: CGColor, bottomColor: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: paneRadius, cornerHeight: paneRadius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))
    ctx.addPath(path)
    ctx.setFillColor(topColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    if let grad = CGGradient(colorsSpace: colorSpace, colors: [topColor, bottomColor] as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    }
    // Tiny window titlebar dots
    let dotY = rect.maxY - 34
    let dotR: CGFloat = 9
    for i in 0..<3 {
        let dotX = rect.minX + 36 + CGFloat(i) * 28
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
        ctx.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
    }
    ctx.restoreGState()
}

drawPane(
    topLeft,
    topColor: CGColor(red: 0.36, green: 0.72, blue: 1.0, alpha: 0.96),
    bottomColor: CGColor(red: 0.20, green: 0.53, blue: 0.95, alpha: 0.96)
)
drawPane(
    topRight,
    topColor: CGColor(red: 0.45, green: 0.85, blue: 0.78, alpha: 0.96),
    bottomColor: CGColor(red: 0.20, green: 0.68, blue: 0.65, alpha: 0.96)
)
drawPane(
    bottomWide,
    topColor: CGColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 0.96),
    bottomColor: CGColor(red: 0.84, green: 0.89, blue: 0.96, alpha: 0.96)
)

guard let cgImage = ctx.makeImage() else {
    fatalError("Failed to make CGImage")
}

let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode PNG")
}

let outPath = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
try pngData.write(to: URL(fileURLWithPath: outPath))
print("Generated \(outPath)")
