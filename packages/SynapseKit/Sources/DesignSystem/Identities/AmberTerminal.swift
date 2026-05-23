import SwiftUI

/// LIFE-identity helpers.
///
/// The Amber-Phosphor Terminal is a single-window experience built around
/// monospaced text and a Metal fragment shader. This file holds the typed
/// shader uniforms struct and the deterministic mapping from environment
/// inputs (Reduce Motion, Reduce Transparency, Increase Contrast) to
/// shader parameters. The mapping is locked by tests so we never ship a
/// build where the accessibility paths regress.
extension TokenSet {

    /// Monospaced typeface used by the LIFE terminal. SF Mono with tabular
    /// digits — every column lines up without padding tricks.
    public func terminalFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
            .monospacedDigit()
    }
}

/// What the LIFE terminal is currently rendering with. The view model
/// publishes this so tests can assert that Reduce Motion drops the
/// shader path entirely rather than just freezing its uniforms.
public enum LifeRenderPath: String, Sendable, Equatable {
    case shader
    case canvasFallback
}

/// Uniforms handed to `LifeTerminal.metal`'s fragment shader. Layout matches
/// the `ShaderUniforms` Metal struct byte-for-byte; if you change one, change
/// both. Fields are exposed as `SIMD*` so Metal's alignment rules apply
/// directly.
public struct ShaderUniforms: Sendable, Equatable {
    public var time: Float
    public var resolution: SIMD2<Float>
    public var bloomRadius: Float
    public var scanlineIntensity: Float
    public var phosphorBright: SIMD4<Float>
    public var phosphorDim: SIMD4<Float>
    public var terminalInk: SIMD4<Float>

    public init(
        time: Float,
        resolution: SIMD2<Float>,
        bloomRadius: Float,
        scanlineIntensity: Float,
        phosphorBright: SIMD4<Float>,
        phosphorDim: SIMD4<Float>,
        terminalInk: SIMD4<Float>
    ) {
        self.time = time
        self.resolution = resolution
        self.bloomRadius = bloomRadius
        self.scanlineIntensity = scanlineIntensity
        self.phosphorBright = phosphorBright
        self.phosphorDim = phosphorDim
        self.terminalInk = terminalInk
    }
}

/// Snapshot of the OS accessibility environment that affects the LIFE
/// shader. The view reads these from `EnvironmentValues` and packages them
/// here so the pure mapping function can be tested without spinning up a
/// real SwiftUI environment.
public struct LifeAccessibilityEnvironment: Sendable, Equatable {
    public var reduceMotion: Bool
    public var reduceTransparency: Bool
    public var increaseContrast: Bool

    public init(
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }
}

public enum LifeShaderUniformBuilder {

    /// `time` value frozen when motion is suppressed. Picked far enough from
    /// zero that the sine in the fragment shader still produces non-zero
    /// phosphor output without animating.
    public static let frozenTime: Float = 0.0

    /// Default radius (in fragment-uv units). Tuned for legibility, not
    /// drama — single-pass 4-tap bloom can only do so much.
    public static let defaultBloomRadius: Float = 1.5

    /// Default scanline contrast. 0.35 is enough to read as a CRT without
    /// punishing the eye.
    public static let defaultScanlineIntensity: Float = 0.35

    /// Build the uniforms struct from the LIFE token set, current time,
    /// drawable size, and accessibility environment. Pure function: the
    /// same inputs always produce the same output. Tests pin this.
    public static func make(
        tokens: LifeIdentityTokens,
        time: Float,
        resolution: SIMD2<Float>,
        accessibility: LifeAccessibilityEnvironment
    ) -> ShaderUniforms {
        // Reduce Motion: freeze time, kill bloom. The shader still draws but
        // produces a flat amber-on-black plate.
        // Reduce Transparency: kill bloom (independent of motion). The
        // bloom approximation is technically a brightness add, not a
        // transparency effect, but it reads as "ghosting" to a transparency-
        // sensitive viewer, so we suppress it on the same signal.
        // Increase Contrast: flatten the scanline. Scanlines reduce
        // effective text contrast for the same reason interlace fields do.
        let frozen = accessibility.reduceMotion
        let bloom: Float = (accessibility.reduceMotion || accessibility.reduceTransparency)
            ? 0.0
            : defaultBloomRadius
        let scan: Float = accessibility.increaseContrast
            ? 0.0
            : defaultScanlineIntensity
        return ShaderUniforms(
            time: frozen ? frozenTime : time,
            resolution: resolution,
            bloomRadius: bloom,
            scanlineIntensity: scan,
            phosphorBright: simd(from: tokens.phosphorBright),
            phosphorDim: simd(from: tokens.phosphorDim),
            terminalInk: simd(from: tokens.terminalInk)
        )
    }

    private static func simd(from token: ColorToken) -> SIMD4<Float> {
        SIMD4(
            Float(token.red),
            Float(token.green),
            Float(token.blue),
            Float(token.opacity)
        )
    }
}
