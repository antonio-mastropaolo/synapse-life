#!/usr/bin/env swift
//
// scripts/make-icons.swift
//
// Re-renders the Synnapse app icon set from source so the design
// language (Cockpit black + amber-phosphor "S") lives in code rather
// than in a binary asset. Run from the repo root:
//
//     swift scripts/make-icons.swift
//
// Writes:
//   apps/Synnapse-iOS/Assets.xcassets/AppIcon.appiconset/synnapse-icon-1024.png
//   apps/Synnapse-macOS/Assets.xcassets/AppIcon.appiconset/icon_{16,32,128,256,512}{,@2x}.png
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
// `swift run` step. Mirrors `packages/SynnapseKit/Sources/Tools/IconRenderer.swift`
// (Palette.phosphor). Keep the two in sync; the canonical version is
// in the package.
enum IconRenderError: Error {
    case contextCreationFailed
    case fontCreationFailed
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

    // Phosphor palette (mirrors IconRenderer.Palette.phosphor)
    let background = CGColor(red: 0.040, green: 0.025, blue: 0.015, alpha: 1.0)
    let scanLine   = CGColor(red: 1.000, green: 0.680, blue: 0.220, alpha: 0.06)
    let glyph      = CGColor(red: 1.000, green: 0.780, blue: 0.300, alpha: 1.0)
    let glow       = CGColor(red: 1.000, green: 0.680, blue: 0.220, alpha: 0.85)
    let cursor     = CGColor(red: 1.000, green: 0.740, blue: 0.250, alpha: 0.92)
    let edge       = CGColor(red: 1.000, green: 0.680, blue: 0.220, alpha: 0.55)

    // Rounded-square tile
    let inset = s * 0.06
    let cornerRadius = s * 0.22
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.setFillColor(background)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // Scan-lines
    ctx.setStrokeColor(scanLine)
    ctx.setLineWidth(s * 0.004)
    var y: CGFloat = s * 0.06
    while y < s {
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: s, y: y))
        ctx.strokePath()
        y += s * 0.022
    }
    ctx.restoreGState()

    // Edge accent
    ctx.addPath(tilePath)
    ctx.setStrokeColor(edge)
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()

    // Bold "S" with bloom
    let fontSize = s * 0.62
    let glyphFont = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: glyphFont,
        kCTForegroundColorAttributeName: glyph
    ]
    guard let attributed = CFAttributedStringCreate(
        kCFAllocatorDefault, "S" as CFString, attrs as CFDictionary
    ) else { throw IconRenderError.fontCreationFailed }
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let drawX = (s - bounds.width) / 2.0 - bounds.origin.x
    let drawY = (s - bounds.height) / 2.0 - bounds.origin.y

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.035, color: glow)
    ctx.textPosition = CGPoint(x: drawX, y: drawY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    ctx.textPosition = CGPoint(x: drawX, y: drawY)
    CTLineDraw(line, ctx)

    // Cursor block
    let cw = s * 0.04
    ctx.setFillColor(cursor)
    ctx.fill(CGRect(x: s * 0.78, y: s * 0.20, width: cw, height: cw))

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
let iosOut = "\(cwd)/apps/Synnapse-iOS/Assets.xcassets/AppIcon.appiconset/synnapse-icon-1024.png"
let macOSDir = "\(cwd)/apps/Synnapse-macOS/Assets.xcassets/AppIcon.appiconset"

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
