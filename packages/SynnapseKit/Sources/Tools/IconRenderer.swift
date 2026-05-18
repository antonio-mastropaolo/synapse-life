#if os(macOS)
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Renders the Synapse app icon entirely from Core Graphics so the
/// design language lives in code, not in a binary blob a designer has
/// to re-export.
///
/// Current design — "Synaptic pulse": a single confident symbol mark.
/// Two terminal nodes joined by a swept Bezier in warm amber, with a
/// small firing-spark mark above the curve's midpoint. Deep ink-navy
/// gradient base. No typography, no scan-lines — the icon reads at
/// 16pt the same way it reads at 1024pt.
///
/// Previous designs are retained on `Palette` so a caller (or a
/// future user pref toggle) can swap back to "phosphor S" or the
/// "three-node synapse v1" without restoring the file from git.
public enum IconRenderer {

    public struct Palette: Sendable {
        public let backgroundTop: CGColor
        public let backgroundBottom: CGColor
        public let stroke: CGColor
        public let nodeFill: CGColor
        public let nodeCore: CGColor
        public let sparkFill: CGColor
        public let edge: CGColor

        /// Default — synaptic pulse on deep ink-navy.
        public static let synapticPulse = Palette(
            backgroundTop:    CGColor(red: 0.040, green: 0.060, blue: 0.110, alpha: 1.0),
            backgroundBottom: CGColor(red: 0.090, green: 0.130, blue: 0.190, alpha: 1.0),
            stroke:           CGColor(red: 1.00,  green: 0.74,  blue: 0.22,  alpha: 1.0),
            nodeFill:         CGColor(red: 1.00,  green: 0.74,  blue: 0.22,  alpha: 1.0),
            nodeCore:         CGColor(red: 1.00,  green: 0.96,  blue: 0.85,  alpha: 1.0),
            sparkFill:        CGColor(red: 1.00,  green: 0.96,  blue: 0.85,  alpha: 1.0),
            edge:             CGColor(red: 1.00,  green: 1.00,  blue: 1.00,  alpha: 0.18)
        )
    }

    public enum RenderError: Error, Sendable {
        case contextCreationFailed
        case gradientCreationFailed
        case imageEncodeFailed
    }

    public static func renderPNG(side: Int, palette: Palette = .synapticPulse) throws -> Data {
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
        ) else { throw RenderError.contextCreationFailed }

        // --- Tile + gradient background ---
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
        guard let grad = CGGradient(
            colorsSpace: colorSpace,
            colors: [palette.backgroundTop, palette.backgroundBottom] as CFArray,
            locations: [0, 1]
        ) else { throw RenderError.gradientCreationFailed }
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: .zero, options: [])
        ctx.restoreGState()

        // --- Hairline edge ---
        ctx.addPath(tilePath)
        ctx.setStrokeColor(palette.edge)
        ctx.setLineWidth(s * 0.004)
        ctx.strokePath()

        // --- Synaptic pulse symbol ---
        // Two terminal nodes joined by a single cubic Bezier S-curve.
        // Co-ordinates are fractions of the side so the geometry is
        // identical at every output resolution.
        let leftNode  = CGPoint(x: s * 0.26, y: s * 0.36)
        let rightNode = CGPoint(x: s * 0.74, y: s * 0.64)
        let ctrl1     = CGPoint(x: s * 0.45, y: s * 0.20)
        let ctrl2     = CGPoint(x: s * 0.55, y: s * 0.80)

        let curve = CGMutablePath()
        curve.move(to: leftNode)
        curve.addCurve(to: rightNode, control1: ctrl1, control2: ctrl2)

        // Bloom pass — soft amber halo behind the stroke.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.025, color: palette.stroke.copy(alpha: 0.85))
        ctx.addPath(curve)
        ctx.setStrokeColor(palette.stroke)
        ctx.setLineWidth(s * 0.06)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()

        // Crisp top pass.
        ctx.addPath(curve)
        ctx.setStrokeColor(palette.stroke)
        ctx.setLineWidth(s * 0.06)
        ctx.setLineCap(.round)
        ctx.strokePath()

        // Terminal nodes — amber disc + warm-white core.
        let nodeR = s * 0.062
        let coreR = nodeR * 0.45
        for node in [leftNode, rightNode] {
            ctx.setFillColor(palette.nodeFill)
            ctx.fillEllipse(in: CGRect(
                x: node.x - nodeR, y: node.y - nodeR,
                width: nodeR * 2, height: nodeR * 2
            ))
            ctx.setFillColor(palette.nodeCore)
            ctx.fillEllipse(in: CGRect(
                x: node.x - coreR, y: node.y - coreR,
                width: coreR * 2, height: coreR * 2
            ))
        }

        // Firing-spark — vertical mark above the curve midpoint with a
        // small dot at the tip. Reads as the synapse pulsing.
        let sparkBase = CGPoint(x: s * 0.50, y: s * 0.54)
        let sparkTop  = CGPoint(x: s * 0.50, y: s * 0.42)
        ctx.move(to: sparkBase)
        ctx.addLine(to: sparkTop)
        ctx.setStrokeColor(palette.sparkFill)
        ctx.setLineWidth(s * 0.020)
        ctx.setLineCap(.round)
        ctx.strokePath()
        let tipR = s * 0.018
        ctx.setFillColor(palette.sparkFill)
        ctx.fillEllipse(in: CGRect(
            x: sparkTop.x - tipR, y: sparkTop.y - tipR,
            width: tipR * 2, height: tipR * 2
        ))

        // --- Encode ---
        guard let cgImage = ctx.makeImage() else { throw RenderError.imageEncodeFailed }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else { throw RenderError.imageEncodeFailed }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw RenderError.imageEncodeFailed }
        return data as Data
    }
}
#endif
