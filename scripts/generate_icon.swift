#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output.icns>\n", stderr)
    exit(1)
}

let outputICNS = URL(fileURLWithPath: CommandLine.arguments[1])

// Apple ICNS modern PNG-backed chunk types (macOS 10.7+)
let entries: [(String, Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
    ("ic11", 32),
    ("ic12", 64),
    ("ic13", 256),
    ("ic14", 512)
]

func renderIconPNGData(pixelSize: Int) -> Data? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let cg = CGContext(
              data: nil,
              width: pixelSize,
              height: pixelSize,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }

    let s = CGFloat(pixelSize)
    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = rect.width * 0.225
    let roundedPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Indigo-to-Cyan modern gradient background
    cg.saveGState()
    cg.addPath(roundedPath)
    cg.clip()
    let colors = [
        CGColor(colorSpace: colorSpace, components: [0.24, 0.27, 0.88, 1.0])!,
        CGColor(colorSpace: colorSpace, components: [0.09, 0.62, 0.86, 1.0])!
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }
    cg.restoreGState()

    // Glass context-menu card on bottom-right
    let cardRect = CGRect(x: s * 0.40, y: s * 0.20, width: s * 0.40, height: s * 0.44)
    let cardPath = CGPath(roundedRect: cardRect, cornerWidth: s * 0.06, cornerHeight: s * 0.06, transform: nil)
    cg.saveGState()
    cg.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.22])!)
    cg.addPath(cardPath)
    cg.fillPath()
    cg.setStrokeColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.48])!)
    cg.setLineWidth(max(1.0, s * 0.015))
    cg.addPath(cardPath)
    cg.strokePath()

    // Three menu lines inside card
    cg.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.90])!)
    let lineX = cardRect.minX + cardRect.width * 0.16
    let lineW = cardRect.width * 0.68
    let lineH = max(1.5, s * 0.036)
    for idx in 0..<3 {
        let y = cardRect.maxY - cardRect.height * (0.28 + CGFloat(idx) * 0.24)
        let lineRect = CGRect(x: lineX, y: y, width: idx == 2 ? lineW * 0.65 : lineW, height: lineH)
        let linePath = CGPath(roundedRect: lineRect, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil)
        cg.addPath(linePath)
        cg.fillPath()
    }
    cg.restoreGState()

    // Crisp minimalist cursor pointer on top-left
    cg.saveGState()
    let cursor = CGMutablePath()
    cursor.move(to: CGPoint(x: s * 0.24, y: s * 0.77))
    cursor.addLine(to: CGPoint(x: s * 0.24, y: s * 0.40))
    cursor.addLine(to: CGPoint(x: s * 0.34, y: s * 0.50))
    cursor.addLine(to: CGPoint(x: s * 0.42, y: s * 0.35))
    cursor.addLine(to: CGPoint(x: s * 0.48, y: s * 0.38))
    cursor.addLine(to: CGPoint(x: s * 0.40, y: s * 0.53))
    cursor.addLine(to: CGPoint(x: s * 0.54, y: s * 0.53))
    cursor.closeSubpath()

    cg.setShadow(
        offset: CGSize(width: 0, height: -s * 0.02),
        blur: s * 0.04,
        color: CGColor(colorSpace: colorSpace, components: [0, 0, 0, 0.28])!
    )
    cg.setFillColor(CGColor(colorSpace: colorSpace, components: [1, 1, 1, 0.98])!)
    cg.addPath(cursor)
    cg.fillPath()
    cg.restoreGState()

    guard let image = cg.makeImage() else { return nil }
    let mutableData = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(mutableData, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return mutableData as Data
}

var renderedBySize: [Int: Data] = [:]
var body = Data()

for (chunkType, pixelSize) in entries {
    let pngData: Data
    if let cached = renderedBySize[pixelSize] {
        pngData = cached
    } else {
        guard let rendered = renderIconPNGData(pixelSize: pixelSize) else {
            fputs("Failed to render \(pixelSize)px icon\n", stderr)
            exit(1)
        }
        renderedBySize[pixelSize] = rendered
        pngData = rendered
    }

    body.append(Data(chunkType.utf8))
    var chunkLength = UInt32(8 + pngData.count).bigEndian
    withUnsafeBytes(of: &chunkLength) { body.append(contentsOf: $0) }
    body.append(pngData)
}

var icns = Data("icns".utf8)
var totalLength = UInt32(8 + body.count).bigEndian
withUnsafeBytes(of: &totalLength) { icns.append(contentsOf: $0) }
icns.append(body)

try icns.write(to: outputICNS, options: .atomic)
