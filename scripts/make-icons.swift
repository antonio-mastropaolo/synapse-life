#!/usr/bin/env swift
//
// scripts/make-icons.swift
//
// Re-renders the Synapse app icon set from source so the design
// language (Cockpit black + amber-phosphor "S") lives in code rather
// than in a binary asset. Run from the repo root:
//
//     swift scripts/make-icons.swift
//
// Writes:
//   apps/Synapse-iOS/Assets.xcassets/AppIcon.appiconset/synapse-icon-1024.png
//   apps/Synapse-macOS/Assets.xcassets/AppIcon.appiconset/icon_{16,32,128,256,512}{,@2x}.png
//
// The renderer itself is `IconRenderer` in the `Tools` SwiftPM target;
// this file is intentionally thin so the design can be tuned by
// editing one Swift file.

import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Inline copy of IconRenderer so the script can run without a SwiftPM
// `swift run` step. Mirrors `packages/SynapseKit/Sources/Tools/IconRenderer.swift`
// (Palette.synapticPulse). Keep the two in sync; the canonical version
// is in the package.
enum IconRenderError: Error {
    case contextCreationFailed
    case gradientCreationFailed
    case imageEncodeFailed
}

func renderIconPNG(side: Int) throws -> Data {
    let s = CGFloat(side)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw IconRenderError.contextCreationFailed }

    // Palette — synaptic pulse on deep ink-navy.
    let bgTop    = CGColor(red: 0.040, green: 0.060, blue: 0.110, alpha: 1.0)
    let bgBottom = CGColor(red: 0.090, green: 0.130, blue: 0.190, alpha: 1.0)
    let stroke   = CGColor(red: 1.00,  green: 0.74,  blue: 0.22,  alpha: 1.0)
    let nodeCore = CGColor(red: 1.00,  green: 0.96,  blue: 0.85,  alpha: 1.0)
    let edge     = CGColor(red: 1.00,  green: 1.00,  blue: 1.00,  alpha: 0.18)

    // Tile + gradient
    let inset = s * 0.06
    let cornerRadius = s * 0.22
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    guard let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [bgTop, bgBottom] as CFArray,
        locations: [0, 1]
    ) else { throw IconRenderError.gradientCreationFailed }
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: .zero, options: [])
    ctx.restoreGState()

    // Hairline edge
    ctx.addPath(tilePath)
    ctx.setStrokeColor(edge)
    ctx.setLineWidth(s * 0.004)
    ctx.strokePath()

    // Synaptic pulse — two nodes joined by a swept Bezier
    let leftNode  = CGPoint(x: s * 0.26, y: s * 0.36)
    let rightNode = CGPoint(x: s * 0.74, y: s * 0.64)
    let ctrl1     = CGPoint(x: s * 0.45, y: s * 0.20)
    let ctrl2     = CGPoint(x: s * 0.55, y: s * 0.80)

    let curve = CGMutablePath()
    curve.move(to: leftNode)
    curve.addCurve(to: rightNode, control1: ctrl1, control2: ctrl2)

    // Bloom pass
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.025, color: stroke.copy(alpha: 0.85))
    ctx.addPath(curve)
    ctx.setStrokeColor(stroke)
    ctx.setLineWidth(s * 0.06)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Crisp top pass
    ctx.addPath(curve)
    ctx.setStrokeColor(stroke)
    ctx.setLineWidth(s * 0.06)
    ctx.setLineCap(.round)
    ctx.strokePath()

    // Terminal nodes
    let nodeR = s * 0.062
    let coreR = nodeR * 0.45
    for node in [leftNode, rightNode] {
        ctx.setFillColor(stroke)
        ctx.fillEllipse(in: CGRect(x: node.x - nodeR, y: node.y - nodeR, width: nodeR * 2, height: nodeR * 2))
        ctx.setFillColor(nodeCore)
        ctx.fillEllipse(in: CGRect(x: node.x - coreR, y: node.y - coreR, width: coreR * 2, height: coreR * 2))
    }

    // Firing spark + tip
    let sparkBase = CGPoint(x: s * 0.50, y: s * 0.54)
    let sparkTop  = CGPoint(x: s * 0.50, y: s * 0.42)
    ctx.move(to: sparkBase)
    ctx.addLine(to: sparkTop)
    ctx.setStrokeColor(nodeCore)
    ctx.setLineWidth(s * 0.020)
    ctx.setLineCap(.round)
    ctx.strokePath()
    let tipR = s * 0.018
    ctx.setFillColor(nodeCore)
    ctx.fillEllipse(in: CGRect(x: sparkTop.x - tipR, y: sparkTop.y - tipR, width: tipR * 2, height: tipR * 2))

    guard let cgImage = ctx.makeImage() else {
        throw IconRenderError.imageEncodeFailed
    }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(
        data as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw IconRenderError.imageEncodeFailed }
    CGImageDestinationAddImage(dest, cgImage, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw IconRenderError.imageEncodeFailed
    }
    return data as Data
}

// Locate the repo root: the script is invoked as
// `swift scripts/make-icons.swift`, so the current working directory
// is the repo root unless the user runs it from elsewhere. We resolve
// relative paths from cwd and create parent directories as needed.
let fm = FileManager.default
let cwd = fm.currentDirectoryPath
let iosOut = "\(cwd)/apps/Synapse-iOS/Assets.xcassets/AppIcon.appiconset/synapse-icon-1024.png"
let macOSDir = "\(cwd)/apps/Synapse-macOS/Assets.xcassets/AppIcon.appiconset"

func ensureDir(_ path: String) throws {
    try fm.createDirectory(
        atPath: path,
        withIntermediateDirectories: true,
        attributes: nil
    )
}

func write(_ data: Data, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try data.write(to: url)
    print("wrote \(path) (\(data.count) bytes)")
}

do {
    // iOS — single 1024 source. Asset catalog handles downscaling.
    try ensureDir((iosOut as NSString).deletingLastPathComponent)
    let ios1024 = try renderIconPNG(side: 1024)
    try write(ios1024, to: iosOut)

    // macOS — explicit set. Apple's macOS icon manifest declares 6
    // sizes at 1x and 2x; we render each at its physical pixel size.
    try ensureDir(macOSDir)
    let macSizes: [(name: String, side: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]
    for entry in macSizes {
        let data = try renderIconPNG(side: entry.side)
        try write(data, to: "\(macOSDir)/\(entry.name)")
    }
} catch {
    FileHandle.standardError.write(Data("make-icons failed: \(error)\n".utf8))
    exit(1)
}
