#if os(macOS)
import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Renders the Synnapse placeholder app icon entirely from Core
/// Graphics so the design language (Cockpit black + amber-phosphor "S")
/// lives in code, not in a binary blob a designer has to re-export.
/// The same renderer drives the `scripts/make-icons.swift` CLI and the
/// per-size resampling that produces the six macOS variants.
public enum IconRenderer {

    public struct Palette: Sendable {
        public let background: CGColor
        public let glyph: CGColor

        /// Cockpit dense default: deep black on the canvas with a
        /// single amber-phosphor capital "S". Matches the LIFE
        /// terminal palette.
        public static let cockpitAmber = Palette(
            background: CGColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.0),
            glyph: CGColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 1.0)
        )
    }

    public enum RenderError: Error, Sendable {
        case contextCreationFailed
        case fontCreationFailed
        case imageEncodeFailed
    }

    /// Renders the icon into a PNG at the given side length. Square,
    /// opaque, no transparency. The glyph is centred and roughly
    /// 70 percent of the canvas side — matches Apple's macOS icon
    /// padding convention.
    public static func renderPNG(side: Int, palette: Palette = .cockpitAmber) throws -> Data {
        let width = side
        let height = side
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.contextCreationFailed
        }

        // Background.
        ctx.setFillColor(palette.background)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Subtle inset rounded square so 1024 -> 16 downscale still
        // reads as an icon and not as a flat black tile. We use a
        // monochrome amber border at ~3 percent of the side.
        let inset = CGFloat(side) * 0.06
        let cornerRadius = CGFloat(side) * 0.18
        let rect = CGRect(
            x: inset,
            y: inset,
            width: CGFloat(width) - inset * 2,
            height: CGFloat(height) - inset * 2
        )
        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(path)
        ctx.setStrokeColor(palette.glyph)
        ctx.setLineWidth(CGFloat(side) * 0.012)
        ctx.strokePath()

        // Glyph. Use the bundled monospaced system font (Menlo) so
        // the icon renders identically on any macOS host without
        // shipping a font asset. Fall back to Courier if Menlo is
        // unavailable for some reason.
        let fontSize = CGFloat(side) * 0.62
        let glyphFont: CTFont = {
            if let f = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
                as CTFont? {
                return f
            }
            return CTFontCreateWithName("Courier-Bold" as CFString, fontSize, nil)
        }()

        // Use CoreText keys directly rather than the AppKit-only
        // `.font` / `.foregroundColor` so this target stays AppKit-free
        // and links the same on iOS host targets too.
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: glyphFont,
            kCTForegroundColorAttributeName: palette.glyph
        ]
        let attributed = CFAttributedStringCreate(
            kCFAllocatorDefault,
            "S" as CFString,
            attrs as CFDictionary
        )
        guard let attributed else { throw RenderError.fontCreationFailed }
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let drawX = (CGFloat(width) - bounds.width) / 2.0 - bounds.origin.x
        let drawY = (CGFloat(height) - bounds.height) / 2.0 - bounds.origin.y
        ctx.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, ctx)

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
