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
// `swift run` step. Mirrors `packages/SynnapseKit/Sources/Tools/IconRenderer.swift`.
// Keep the two in sync; the canonical version is in the package.
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

    // Palette (mirrors IconRenderer.Palette.synapse)
    let bgTop    = CGColor(red: 0.040, green: 0.110, blue: 0.165, alpha: 1.0)
    let bgBottom = CGColor(red: 0.085, green: 0.215, blue: 0.290, alpha: 1.0)
    let hubFill  = CGColor(red: 1.000, green: 0.690, blue: 0.220, alpha: 1.0)
    let hubCore  = CGColor(red: 1.000, green: 0.960, blue: 0.880, alpha: 1.0)
    let satA     = CGColor(red: 0.270, green: 0.830, blue: 0.890, alpha: 1.0)
    let satB     = CGColor(red: 0.945, green: 0.330, blue: 0.560, alpha: 1.0)
    let connector = CGColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.65)

    // Rounded-square tile + clipped gradient fill
    let inset = s * 0.06
    let cornerRadius = s * 0.22
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = CGPath(
        roundedRect: tile,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [bgTop, bgBottom] as CFArray,
        locations: [0.0, 1.0]
    ) else { throw IconRenderError.gradientCreationFailed }
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    ctx.restoreGState()

    // Hairline edge
    ctx.addPath(tilePath)
    ctx.setStrokeColor(connector)
    ctx.setLineWidth(s * 0.004)
    ctx.strokePath()

    // Three-node synapse geometry
    let cx = s / 2
    let hubRadius = s * 0.13
    let satRadius = s * 0.07
    let hubCenter = CGPoint(x: cx, y: s * 0.62)
    let satAP = CGPoint(x: s * 0.30, y: s * 0.30)
    let satBP = CGPoint(x: s * 0.70, y: s * 0.30)

    // Connectors
    ctx.setLineCap(.round)
    ctx.setStrokeColor(connector)
    ctx.setLineWidth(s * 0.014)
    for pair in [(hubCenter, satAP), (hubCenter, satBP), (satAP, satBP)] {
        ctx.move(to: pair.0)
        ctx.addLine(to: pair.1)
        ctx.strokePath()
    }

    // Hub (outer fill + core)
    ctx.setFillColor(hubFill)
    ctx.fillEllipse(in: CGRect(
        x: hubCenter.x - hubRadius,
        y: hubCenter.y - hubRadius,
        width: hubRadius * 2,
        height: hubRadius * 2
    ))
    let coreRadius = hubRadius * 0.45
    ctx.setFillColor(hubCore)
    ctx.fillEllipse(in: CGRect(
        x: hubCenter.x - coreRadius,
        y: hubCenter.y - coreRadius,
        width: coreRadius * 2,
        height: coreRadius * 2
    ))

    // Satellites
    for (center, color) in [(satAP, satA), (satBP, satB)] {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(
            x: center.x - satRadius,
            y: center.y - satRadius,
            width: satRadius * 2,
            height: satRadius * 2
        ))
    }

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
