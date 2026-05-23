import Foundation
import Testing
@testable import DesignSystem

private let life = LifeIdentityTokens(
    phosphorBright: ColorToken(1.00, 0.478, 0.000),
    phosphorDim:    ColorToken(0.700, 0.329, 0.000),
    terminalInk:    ColorToken(0.031, 0.024, 0.016)
)

@Suite("LifeShaderUniforms")
struct LifeShaderUniformsTests {

    @Test
    func defaultsCarryColorsAndAnimateTime() {
        let u = LifeShaderUniformBuilder.make(
            tokens: life,
            time: 12.5,
            resolution: SIMD2<Float>(800, 600),
            accessibility: LifeAccessibilityEnvironment()
        )
        #expect(u.time == 12.5)
        #expect(u.resolution == SIMD2<Float>(800, 600))
        #expect(u.bloomRadius == LifeShaderUniformBuilder.defaultBloomRadius)
        #expect(u.scanlineIntensity == LifeShaderUniformBuilder.defaultScanlineIntensity)
        #expect(u.phosphorBright == SIMD4<Float>(1.00, 0.478, 0.000, 1.0))
        #expect(u.phosphorDim    == SIMD4<Float>(0.700, 0.329, 0.000, 1.0))
        #expect(u.terminalInk    == SIMD4<Float>(0.031, 0.024, 0.016, 1.0))
    }

    @Test
    func reduceMotionFreezesTimeAndKillsBloom() {
        let u = LifeShaderUniformBuilder.make(
            tokens: life,
            time: 99.0,
            resolution: SIMD2<Float>(400, 300),
            accessibility: LifeAccessibilityEnvironment(reduceMotion: true)
        )
        #expect(u.time == LifeShaderUniformBuilder.frozenTime)
        #expect(u.bloomRadius == 0.0)
        // Scanlines still allowed under Reduce Motion (they don't move).
        #expect(u.scanlineIntensity == LifeShaderUniformBuilder.defaultScanlineIntensity)
    }

    @Test
    func reduceTransparencyKillsBloomIndependentOfMotion() {
        let u = LifeShaderUniformBuilder.make(
            tokens: life,
            time: 5.0,
            resolution: SIMD2<Float>(400, 300),
            accessibility: LifeAccessibilityEnvironment(reduceTransparency: true)
        )
        #expect(u.bloomRadius == 0.0)
        // Time still animates under Reduce Transparency.
        #expect(u.time == 5.0)
    }

    @Test
    func increaseContrastFlattensScanline() {
        let u = LifeShaderUniformBuilder.make(
            tokens: life,
            time: 5.0,
            resolution: SIMD2<Float>(400, 300),
            accessibility: LifeAccessibilityEnvironment(increaseContrast: true)
        )
        #expect(u.scanlineIntensity == 0.0)
        // Bloom and time still on under Increase Contrast.
        #expect(u.bloomRadius == LifeShaderUniformBuilder.defaultBloomRadius)
        #expect(u.time == 5.0)
    }

    @Test
    func allThreeAccessibilityFlagsCompose() {
        let u = LifeShaderUniformBuilder.make(
            tokens: life,
            time: 5.0,
            resolution: SIMD2<Float>(400, 300),
            accessibility: LifeAccessibilityEnvironment(
                reduceMotion: true,
                reduceTransparency: true,
                increaseContrast: true
            )
        )
        #expect(u.time == LifeShaderUniformBuilder.frozenTime)
        #expect(u.bloomRadius == 0.0)
        #expect(u.scanlineIntensity == 0.0)
    }
}
