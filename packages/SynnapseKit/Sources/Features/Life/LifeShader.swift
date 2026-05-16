#if canImport(Metal)
import Foundation
import Metal
import MetalKit
import CoreGraphics
import ImageIO
import DesignSystem

/// Metal pipeline for the LIFE Amber-Phosphor Terminal.
///
/// Owns the device, library, and pipeline state. The view wires uniforms
/// per frame via `render(uniforms:size:glyphTexture:)` and either pushes
/// the result into an `MTKView` drawable (interactive path) or asks the
/// shader for a `CGImage` (tests / `ImageRenderer` path).
///
/// The Metal device, library, and pipeline are constructed eagerly in
/// `init` so failures surface at the call site as a typed `Error` instead
/// of a silent black frame at draw time.
public final class LifeShader: @unchecked Sendable {

    public enum Error: Swift.Error, Equatable {
        case metalUnavailable
        case libraryMissing
        case functionMissing(String)
        case pipelineFailed(String)
        case renderFailed
        case textureFailed
    }

    public let device: MTLDevice
    private let library: MTLLibrary
    private let pipelineState: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue
    private let pixelFormat: MTLPixelFormat = .bgra8Unorm

    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw Error.metalUnavailable
        }
        self.device = device

        // SwiftPM does not (today) compile loose `.metal` files in a
        // library target into a `default.metallib` inside the bundle —
        // it copies them as plain resources. So we read the source at
        // runtime and ask the device to compile it. The cost is paid
        // once at init; the typed `Error.libraryMissing` /
        // `pipelineFailed` paths surface any toolchain breakage.
        //
        // Production app targets that have the .metal in their own
        // app bundle (compiled by Xcode) get the cheaper
        // `device.makeDefaultLibrary()` path automatically.
        let library: MTLLibrary
        if let url = Bundle.module.url(forResource: "LifeTerminal", withExtension: "metal", subdirectory: "Shaders")
            ?? Bundle.module.url(forResource: "LifeTerminal", withExtension: "metal"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            do {
                library = try device.makeLibrary(source: source, options: nil)
            } catch {
                throw Error.pipelineFailed("metal compile failed: \(error)")
            }
        } else if let defaultLibrary = device.makeDefaultLibrary(),
                  defaultLibrary.makeFunction(name: "life_vertex") != nil {
            library = defaultLibrary
        } else {
            throw Error.libraryMissing
        }
        self.library = library

        guard let vertexFn = library.makeFunction(name: "life_vertex") else {
            throw Error.functionMissing("life_vertex")
        }
        guard let fragmentFn = library.makeFunction(name: "life_fragment") else {
            throw Error.functionMissing("life_fragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        // Premultiplied-alpha blending — matches what AppKit / UIKit expect
        // when we hand them a CGImage built from this output.
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw Error.pipelineFailed(String(describing: error))
        }

        guard let queue = device.makeCommandQueue() else {
            throw Error.pipelineFailed("makeCommandQueue returned nil")
        }
        self.commandQueue = queue
    }

    /// Off-screen render to a `CGImage`. Used by snapshot tests and by the
    /// `Canvas` fallback path when the platform refuses Metal at runtime.
    public func render(
        uniforms: ShaderUniforms,
        size: CGSize,
        glyphTexture: MTLTexture? = nil
    ) throws -> CGImage {
        let width = max(1, Int(size.width))
        let height = max(1, Int(size.height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        // Shared storage so the host can `getBytes` after the command
        // buffer commits. Private storage would require a blit-into-buffer
        // step that is overkill for off-screen testing.
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor) else {
            throw Error.textureFailed
        }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = target
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(uniforms.terminalInk.x),
            green: Double(uniforms.terminalInk.y),
            blue: Double(uniforms.terminalInk.z),
            alpha: 1.0
        )

        guard let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            throw Error.renderFailed
        }

        encoder.setRenderPipelineState(pipelineState)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
        let glyph = try glyphTexture ?? makeWhiteTexture(width: width, height: height)
        encoder.setFragmentTexture(glyph, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        return try makeImage(from: target)
    }

    private func makeWhiteTexture(width: Int, height: Int) throws -> MTLTexture {
        // 1x1 white texture — the shader will scale-sample it as a uniform
        // phosphor plate. Used by the shader-reference snapshot.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 1, height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Error.textureFailed
        }
        var byte: UInt8 = 255
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &byte,
            bytesPerRow: 1
        )
        return texture
    }

    private func makeImage(from texture: MTLTexture) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(
            &data,
            bytesPerRow: bytesPerRow,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        // Texture is bgra8Unorm; swap to rgba for CGImage.
        for i in stride(from: 0, to: data.count, by: 4) {
            let b = data[i]
            let r = data[i + 2]
            data[i] = r
            data[i + 2] = b
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let provider = CGDataProvider(data: Data(data) as CFData) else {
            throw Error.renderFailed
        }
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw Error.renderFailed
        }
        return image
    }
}
#else
import Foundation
import DesignSystem
import CoreGraphics

public final class LifeShader: @unchecked Sendable {
    public enum Error: Swift.Error, Equatable {
        case metalUnavailable
        case libraryMissing
        case functionMissing(String)
        case pipelineFailed(String)
        case renderFailed
        case textureFailed
    }

    public init() throws {
        throw Error.metalUnavailable
    }

    public func render(uniforms: ShaderUniforms, size: CGSize) throws -> CGImage {
        throw Error.metalUnavailable
    }
}
#endif
