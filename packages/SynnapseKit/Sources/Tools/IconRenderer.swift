#if os(macOS)
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Renders the Synapse app icon entirely from Core Graphics so the
/// design language lives in code, not in a binary blob a designer has
/// to re-export.
///
/// Current design — "Phosphor terminal":
///   • Near-black background, subtly warmed amber, with horizontal
///     scan-lines drawn at low alpha.
///   • Bold Menlo capital "S" in phosphor amber with a soft bloom so
///     the glyph reads as glowing at every size.
///   • Small amber cursor block in the lower-right corner — the same
///     terminal-cursor language the LIFE surface uses.
///
/// The previous "three-node synapse" palette is retained as
/// `Palette.synapseV1` so the alternate look can be re-rendered
/// without recovering the file from git history. Switching designs
/// is a one-line change at the call site in `scripts/make-icons.swift`.
public enum IconRenderer {

    public struct Palette: Sendable {
        public let background: CGColor
        public let scanLine: CGColor
        public let glyph: CGColor
        public let glow: CGColor
        public let cursor: CGColor
        public let edge: CGColor

        /// Default — phosphor amber on near-black with subtle scan-lines.
        public static let phosphor = Palette(
            background: CGColor(red: 0.040, green: 0.025, blue: 0.015, alpha: 1.0),
            scanLine:   CGColor(red: 1.000, green: 0.680, blue: 0.220, alpha: 0.06),
            glyph:      CGColor(red: 1.000, green: 0.780, blue: 0.300, alpha: 1.0),
            glow:       CGColor(red: 1.000, green: 0.680, blue: 0.220, alpha: 0.85),
            cursor:     CGColor(red: 1.000, green: 0.740, blue: 0.250, alpha: 0.92),
            edge:       CGColor(red: 1.000, green: 0.680, blue: 0.220, alpha: 0.55)
        )

        /// Legacy 2026-05-18 three-node synapse mark. Retained so a
        /// caller (or a future user pref toggle) can ship that design
        /// instead of the phosphor one without restoring the file.
        public static let synapseV1 = Palette(
            background: CGColor(red: 0.040, green: 0.110, blue: 0.165, alpha: 1.0),
            scanLine:   CGColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.0),
            glyph:      CGColor(red: 1.000, green: 0.690, blue: 0.220, alpha: 1.0),
            glow:       CGColor(red: 1.000, green: 0.960, blue: 0.880, alpha: 1.0),
            cursor:     CGColor(red: 0.270, green: 0.830, blue: 0.890, alpha: 1.0),
            edge:       CGColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.65)
        )
    }

    public enum RenderError: Error, Sendable {
        case contextCreationFailed
        case fontCreationFailed
        case imageEncodeFailed
    }

    /// Renders the icon into a PNG at the given side length. Square,
    /// opaque, no transparency. Geometry is in fractions of the side
    /// so 16pt and 1024pt read consistently.
    public static func renderPNG(side: Int, palette: Palette = .phosphor) throws -> Data {
        let s = CGFloat(side)
        let bytesPerRow = side * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.contextCreationFailed
        }

        // --- Tile + background ---
        let inset = s * 0.06
        let cornerRadius = s * 0.22
        let tile = CGRect(
            x: inset, y: inset,
            width: s - inset * 2, height: s - inset * 2
        )
        let tilePath = CGPath(
            roundedRect: tile,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()
        ctx.setFillColor(palette.background)
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

        // --- Scan-lines ---
        ctx.setStrokeColor(palette.scanLine)
        ctx.setLineWidth(s * 0.004)
        var y: CGFloat = s * 0.06
        while y < s {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: s, y: y))
            ctx.strokePath()
            y += s * 0.022
        }
        ctx.restoreGState()

        // --- Edge ---
        ctx.addPath(tilePath)
        ctx.setStrokeColor(palette.edge)
        ctx.setLineWidth(s * 0.006)
        ctx.strokePath()

        // --- Glyph "S" with bloom ---
        let fontSize = s * 0.62
        let glyphFont: CTFont = {
            if let f = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil) as CTFont? {
                return f
            }
            return CTFontCreateWithName("Courier-Bold" as CFString, fontSize, nil)
        }()
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: glyphFont,
            kCTForegroundColorAttributeName: palette.glyph
        ]
        guard let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            "S" as CFString,
            attrs as CFDictionary
        ) else { throw RenderError.fontCreationFailed }
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let drawX = (s - bounds.width) / 2.0 - bounds.origin.x
        let drawY = (s - bounds.height) / 2.0 - bounds.origin.y

        // Bloom pass
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.035, color: palette.glow)
        ctx.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, ctx)
        ctx.restoreGState()

        // Crisp top pass
        ctx.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, ctx)

        // --- Cursor block ---
        let cw = s * 0.04
        ctx.setFillColor(palette.cursor)
        ctx.fill(CGRect(x: s * 0.78, y: s * 0.20, width: cw, height: cw))

        // --- Encode ---
        guard let cgImage = ctx.makeImage() else {
            throw RenderError.imageEncodeFailed
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RenderError.imageEncodeFailed
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw RenderError.imageEncodeFailed
        }
        return data as Data
    }
}
#endif
