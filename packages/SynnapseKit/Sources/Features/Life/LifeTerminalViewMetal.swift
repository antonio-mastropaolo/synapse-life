#if canImport(MetalKit)
import SwiftUI
import Metal
import MetalKit
import DesignSystem

#if os(macOS)
import AppKit
typealias LifeMetalViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias LifeMetalViewRepresentable = UIViewRepresentable
#endif

/// Drives the LIFE Metal plate. The plate is a single full-screen amber
/// phosphor surface — bloom, scanline, decay — that sits BEHIND the
/// SwiftUI text layer rendered by `LifeTerminalView`. We do not rasterize
/// the text into a Metal texture in M6; that compositing pass is M9.
@MainActor
struct LifeTerminalViewMetal: LifeMetalViewRepresentable {

    let tokens: LifeIdentityTokens
    let accessibility: LifeAccessibilityEnvironment

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var device: MTLDevice?
        var pipelineState: MTLRenderPipelineState?
        var commandQueue: MTLCommandQueue?
        var whiteTexture: MTLTexture?
        var startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
        var tokens: LifeIdentityTokens
        var accessibility: LifeAccessibilityEnvironment

        init(tokens: LifeIdentityTokens, accessibility: LifeAccessibilityEnvironment) {
            self.tokens = tokens
            self.accessibility = accessibility
        }

        func configure(view: MTKView) {
            guard let device = MTLCreateSystemDefaultDevice() else { return }
            self.device = device
            view.device = device
            view.colorPixelFormat = .bgra8Unorm
            view.framebufferOnly = true
            view.isPaused = accessibility.reduceMotion
            view.enableSetNeedsDisplay = accessibility.reduceMotion
            view.preferredFramesPerSecond = 60
            self.commandQueue = device.makeCommandQueue()
            self.whiteTexture = LifeTerminalViewMetal.makeWhitePlate(device: device)
            self.pipelineState = LifeTerminalViewMetal.makePipeline(device: device)
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { drawIsolated(in: view) }
        }

        private func drawIsolated(in view: MTKView) {
            guard let device = device,
                  let pipelineState = pipelineState,
                  let queue = commandQueue,
                  let drawable = view.currentDrawable,
                  let descriptor = view.currentRenderPassDescriptor,
                  let whiteTexture = whiteTexture else { return }
            let size = view.drawableSize
            let elapsed = Float(CFAbsoluteTimeGetCurrent() - startTime)
            var uniforms = LifeShaderUniformBuilder.make(
                tokens: tokens,
                time: elapsed,
                resolution: SIMD2<Float>(Float(size.width), Float(size.height)),
                accessibility: accessibility
            )
            descriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: Double(uniforms.terminalInk.x),
                green: Double(uniforms.terminalInk.y),
                blue: Double(uniforms.terminalInk.z),
                alpha: 1.0
            )
            guard let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            encoder.setRenderPipelineState(pipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShaderUniforms>.stride, index: 0)
            encoder.setFragmentTexture(whiteTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
            _ = device // silence unused warning on some toolchains
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tokens: tokens, accessibility: accessibility)
    }

    #if os(macOS)
    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.configure(view: view)
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.tokens = tokens
        context.coordinator.accessibility = accessibility
        nsView.isPaused = accessibility.reduceMotion
        nsView.enableSetNeedsDisplay = accessibility.reduceMotion
    }
    #else
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        context.coordinator.configure(view: view)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.tokens = tokens
        context.coordinator.accessibility = accessibility
        uiView.isPaused = accessibility.reduceMotion
        uiView.enableSetNeedsDisplay = accessibility.reduceMotion
    }
    #endif

    // MARK: - shared pipeline construction

    static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        // Mirrors `LifeShader.init`: read the .metal source at runtime
        // because SwiftPM does not pre-compile loose Metal files for
        // library targets. App targets that bundle the .metal in their
        // own asset catalog get the cheaper default-library path.
        let library: MTLLibrary?
        if let url = Bundle.module.url(forResource: "LifeTerminal", withExtension: "metal", subdirectory: "Shaders")
            ?? Bundle.module.url(forResource: "LifeTerminal", withExtension: "metal"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            library = try? device.makeLibrary(source: source, options: nil)
        } else {
            library = device.makeDefaultLibrary()
        }
        guard let library,
              let vertexFn = library.makeFunction(name: "life_vertex"),
              let fragmentFn = library.makeFunction(name: "life_fragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    static func makeWhitePlate(device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: 1, height: 1,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var byte: UInt8 = 255
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &byte,
            bytesPerRow: 1
        )
        return texture
    }
}
#endif
