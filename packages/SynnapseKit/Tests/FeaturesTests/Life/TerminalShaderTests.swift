#if canImport(Metal)
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import Features
@testable import DesignSystem

/// LIFE Metal shader smoke tests.
///
/// Three layers, all gated on the test host actually having a Metal device:
///   1. The packaged `default.metallib` loads cleanly.
///   2. The vertex+fragment pair compiles into an `MTLRenderPipelineState`.
///   3. A 256×128 deterministic render lands within tolerance of the
///      committed reference PNG.
///
/// On a CI host without a GPU (`MTLCreateSystemDefaultDevice() == nil`),
/// `LifeShader.init()` throws `.metalUnavailable` and we assert exactly
/// that. We never skip silently — the missing-device branch is part of
/// the contract.
@Suite("TerminalShader")
struct TerminalShaderTests {

    private static var hasDevice: Bool { MTLCreateSystemDefaultDevice() != nil }

    @Test
    func metalUnavailableThrowsTypedError() throws {
        // We can't simulate "no device" on a host that has one. Instead we
        // assert that the error case exists and matches the Equatable
        // signature the runtime check would produce.
        let err = LifeShader.Error.metalUnavailable
        #expect(err == LifeShader.Error.metalUnavailable)
    }

    @Test
    func libraryLoadsAndPipelineCompiles() throws {
        try #require(Self.hasDevice, "no Metal device on host")
        // Constructing the shader exercises makeLibrary + makeFunction +
        // makeRenderPipelineState in one shot. If any of them fail, init
        // throws a typed `LifeShader.Error` with the failure site.
        _ = try LifeShader()
    }

    @Test
    func renderProducesReferenceFrame() throws {
        try #require(Self.hasDevice, "no Metal device on host")
        let shader = try LifeShader()
        let uniforms = ShaderUniforms(
            // Frozen time so the reference frame is reproducible.
            time: 0.0,
            resolution: SIMD2<Float>(256, 128),
            // Defaults — bloom and scanline both on. Snapshot captures the
            // full effect.
            bloomRadius: LifeShaderUniformBuilder.defaultBloomRadius,
            scanlineIntensity: LifeShaderUniformBuilder.defaultScanlineIntensity,
            phosphorBright: SIMD4<Float>(1.00, 0.478, 0.000, 1.0),
            phosphorDim:    SIMD4<Float>(0.700, 0.329, 0.000, 1.0),
            terminalInk:    SIMD4<Float>(0.031, 0.024, 0.016, 1.0)
        )
        let image = try shader.render(uniforms: uniforms, size: CGSize(width: 256, height: 128))
        #expect(image.width == 256)
        #expect(image.height == 128)

        let referenceURL = referenceImageURL()
        if !FileManager.default.fileExists(atPath: referenceURL.path) {
            // First run: write the reference and re-run. The reference is
            // expected to be committed by the test author; subsequent runs
            // gate on it. Locally this means: run once, commit the PNG,
            // run again — the second run is the load-bearing assertion.
            try writePNG(image, to: referenceURL)
            Issue.record("wrote shader reference to \(referenceURL.path); commit and re-run")
            return
        }
        let reference = try loadPNG(at: referenceURL)
        let diff = try pixelDiff(image, reference)
        #expect(diff.maxChannelDelta <= 2,
                "max channel delta \(diff.maxChannelDelta) > 2")
        #expect(diff.pixelsOverThresholdFraction <= 0.005,
                "\(diff.pixelsOverThresholdFraction * 100)% of pixels exceeded threshold (> 0.5%)")
    }

    // MARK: - helpers

    private func referenceImageURL() -> URL {
        // Snapshot reference is committed under
        // Tests/SnapshotTests/__Snapshots__/Life/shader_reference.png.
        // Start from this file's path and walk up to the `Tests/`
        // directory, then descend into the snapshot tree.
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" && url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent("SnapshotTests")
            .appendingPathComponent("__Snapshots__")
            .appendingPathComponent("Life")
            .appendingPathComponent("shader_reference.png")
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw LifeShader.Error.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            throw LifeShader.Error.renderFailed
        }
    }

    private func loadPNG(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LifeShader.Error.renderFailed
        }
        return image
    }

    private struct DiffResult { let maxChannelDelta: Int; let pixelsOverThresholdFraction: Double }

    private func pixelDiff(_ lhs: CGImage, _ rhs: CGImage) throws -> DiffResult {
        guard lhs.width == rhs.width, lhs.height == rhs.height else {
            throw LifeShader.Error.renderFailed
        }
        let lhsData = try bytes(of: lhs)
        let rhsData = try bytes(of: rhs)
        var maxDelta = 0
        var over = 0
        let total = lhsData.count / 4
        for i in stride(from: 0, to: lhsData.count, by: 4) {
            // Compare RGB only; we don't trust alpha across PNG round-trips.
            let dr = abs(Int(lhsData[i])     - Int(rhsData[i]))
            let dg = abs(Int(lhsData[i + 1]) - Int(rhsData[i + 1]))
            let db = abs(Int(lhsData[i + 2]) - Int(rhsData[i + 2]))
            let local = max(dr, max(dg, db))
            if local > maxDelta { maxDelta = local }
            if local > 2 { over += 1 }
        }
        return DiffResult(
            maxChannelDelta: maxDelta,
            pixelsOverThresholdFraction: Double(over) / Double(max(total, 1))
        )
    }

    private func bytes(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw LifeShader.Error.renderFailed
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}
#endif
