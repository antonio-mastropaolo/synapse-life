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
/// Composition: three connected "synapse nodes" arranged in a
/// downward-pointing triangle (one large hub, two smaller satellites)
/// on a vertical gradient base. Reads as a stylised neural junction —
/// on-brand for the project name, and visually distinct from the
/// previous "amber S on black" placeholder which had no semantic load.
///
/// The same renderer drives `scripts/make-icons.swift` (which exports
/// the full @1x / @2x / large.png set into the .appiconset folders).
public enum IconRenderer {

    public struct Palette: Sendable {
        public let backgroundTop: CGColor
        public let backgroundBottom: CGColor
        public let hubFill: CGColor
        public let hubCore: CGColor
        public let satelliteA: CGColor
        public let satelliteB: CGColor
        public let connector: CGColor

        /// Default: deep teal-navy base, amber hub, cyan + magenta
        /// satellites. Keeps the historical amber accent (the LIFE
        /// terminal heritage) but layers it onto a richer multi-hue
        /// palette so the icon doesn't read as "single-color dev
        /// placeholder" any more.
        public static let synapse = Palette(
            backgroundTop:    CGColor(red: 0.040, green: 0.110, blue: 0.165, alpha: 1.0),  // #0A1C2A
            backgroundBottom: CGColor(red: 0.085, green: 0.215, blue: 0.290, alpha: 1.0),  // #163749
            hubFill:          CGColor(red: 1.000, green: 0.690, blue: 0.220, alpha: 1.0),  // #FFB038 — amber hub
            hubCore:          CGColor(red: 1.000, green: 0.960, blue: 0.880, alpha: 1.0),  // warm white core glow
            satelliteA:       CGColor(red: 0.270, green: 0.830, blue: 0.890, alpha: 1.0),  // #45D4E3 — cyan
            satelliteB:       CGColor(red: 0.945, green: 0.330, blue: 0.560, alpha: 1.0),  // #F1548F — magenta
            connector:        CGColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.65)
        )

        /// Legacy single-tone fallback. Retained so anything that
        /// still references `.cockpitAmber` keeps compiling while the
        /// new default rolls out.
        public static let cockpitAmber = Palette(
            backgroundTop:    CGColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1.0),
            backgroundBottom: CGColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1.0),
            hubFill:          CGColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 1.0),
            hubCore:          CGColor(red: 1.00, green: 0.85, blue: 0.45, alpha: 1.0),
            satelliteA:       CGColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 1.0),
            satelliteB:       CGColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 1.0),
            connector:        CGColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 0.65)
        )
    }

    public enum RenderError: Error, Sendable {
        case contextCreationFailed
        case gradientCreationFailed
        case imageEncodeFailed
    }

    /// Renders the icon into a PNG at the given side length. Square,
    /// opaque, no transparency. Geometry is in fractions of the side
    /// so every output (16pt, 1024pt) reads consistently.
    public static func renderPNG(side: Int, palette: Palette = .synapse) throws -> Data {
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

        // -- Background: rounded-square tile with vertical gradient --
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

        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [palette.backgroundTop, palette.backgroundBottom] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            throw RenderError.gradientCreationFailed
        }
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
        ctx.restoreGState()

        // Subtle outer hairline so the icon retains a defined edge
        // even when the OS composites it on a light Finder background.
        ctx.addPath(tilePath)
        ctx.setStrokeColor(palette.connector)
        ctx.setLineWidth(s * 0.004)
        ctx.strokePath()

        // -- Geometry of the three nodes --
        //
        // Triangle composition: hub at upper-center, two satellites
        // bottom-left / bottom-right. The hub is ~26% diameter; each
        // satellite is ~14% diameter. Connectors are 1.4% line width.
        let cx = s / 2
        let hubRadius = s * 0.13
        let satRadius = s * 0.07

        let hubCenter = CGPoint(x: cx, y: s * 0.62)
        let satA = CGPoint(x: s * 0.30, y: s * 0.30)  // bottom-left
        let satB = CGPoint(x: s * 0.70, y: s * 0.30)  // bottom-right

        // -- Connectors first (so the nodes paint over the endpoints) --
        ctx.setLineCap(.round)
        ctx.setStrokeColor(palette.connector)
        ctx.setLineWidth(s * 0.014)
        for pair in [(hubCenter, satA), (hubCenter, satB), (satA, satB)] {
            ctx.move(to: pair.0)
            ctx.addLine(to: pair.1)
            ctx.strokePath()
        }

        // -- Hub: outer fill, then warm core --
        ctx.setFillColor(palette.hubFill)
        ctx.fillEllipse(in: CGRect(
            x: hubCenter.x - hubRadius,
            y: hubCenter.y - hubRadius,
            width: hubRadius * 2,
            height: hubRadius * 2
        ))
        let coreRadius = hubRadius * 0.45
        ctx.setFillColor(palette.hubCore)
        ctx.fillEllipse(in: CGRect(
            x: hubCenter.x - coreRadius,
            y: hubCenter.y - coreRadius,
            width: coreRadius * 2,
            height: coreRadius * 2
        ))

        // -- Satellites --
        for (center, color) in [(satA, palette.satelliteA), (satB, palette.satelliteB)] {
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(
                x: center.x - satRadius,
                y: center.y - satRadius,
                width: satRadius * 2,
                height: satRadius * 2
            ))
        }

        // -- Encode --
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
