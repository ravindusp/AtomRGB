import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else {
    fputs("usage: compose_dmg_background.swift <base> <logo> <output>\n", stderr)
    exit(2)
}

func loadImage(at path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path) else {
        fputs("Unable to load image: \(path)\n", stderr)
        exit(1)
    }

    var proposedRect = NSRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
        fputs("Unable to decode image: \(path)\n", stderr)
        exit(1)
    }
    return cgImage
}

let base = loadImage(at: CommandLine.arguments[1])
let logo = loadImage(at: CommandLine.arguments[2])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])

let canvasSize = CGSize(width: 1200, height: 675)
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: Int(canvasSize.width),
    height: Int(canvasSize.height),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Unable to create drawing context\n", stderr)
    exit(1)
}

context.interpolationQuality = .high
context.draw(base, in: CGRect(origin: .zero, size: canvasSize))

// The supplied logo has a dark square backdrop. Screen blending turns that
// backdrop into a subtle watermark while preserving the exact colorful mark.
context.saveGState()
context.setBlendMode(.screen)
context.setAlpha(0.22)
context.draw(logo, in: CGRect(x: 485, y: 405, width: 230, height: 230))
context.restoreGState()

// Finder uses dark label text for custom icon views on some macOS versions.
// These quiet frosted plates keep the two labels readable without competing
// with the artwork or the central arrow.
func drawLabelPlate(_ rect: CGRect) {
    context.saveGState()
    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.18))
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.22))
    context.setLineWidth(1)
    context.addPath(CGPath(
        roundedRect: rect,
        cornerWidth: 18,
        cornerHeight: 18,
        transform: nil
    ))
    context.drawPath(using: .fillStroke)
    context.restoreGState()
}

drawLabelPlate(CGRect(x: 172, y: 220, width: 256, height: 52))
drawLabelPlate(CGRect(x: 772, y: 220, width: 256, height: 52))

// A clean, Finder-background arrow gives the two standard DMG items a clear
// install path without depending on an icon font or a third-party DMG tool.
context.saveGState()
context.setStrokeColor(CGColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.82))
context.setLineWidth(5)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: CGColor(gray: 0, alpha: 0.5))

let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 475, y: 325))
arrow.addLine(to: CGPoint(x: 725, y: 325))
arrow.move(to: CGPoint(x: 680, y: 365))
arrow.addLine(to: CGPoint(x: 725, y: 325))
arrow.addLine(to: CGPoint(x: 680, y: 285))
context.addPath(arrow)
context.strokePath()
context.restoreGState()

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Unable to create output image: \(outputURL.path)\n", stderr)
    exit(1)
}

guard let outputImage = context.makeImage() else {
    fputs("Unable to finalize output image\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write output image: \(outputURL.path)\n", stderr)
    exit(1)
}
