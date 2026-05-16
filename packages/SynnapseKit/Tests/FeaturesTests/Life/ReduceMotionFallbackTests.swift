import Foundation
import Testing
@testable import Networking
@testable import Features
@testable import DesignSystem

@MainActor
@Suite("ReduceMotionFallback")
struct ReduceMotionFallbackTests {

    @Test
    func reduceMotionForcesCanvasFallback() {
        let vm = LifeViewModel(api: MockLifeAPI())
        vm.updateRenderPath(
            accessibility: LifeAccessibilityEnvironment(reduceMotion: true)
        )
        #expect(vm.currentRenderPath == .canvasFallback)
    }

    @Test
    func reduceTransparencyAloneKeepsShader() {
        // Reduce Transparency suppresses bloom inside the shader but does
        // not switch render paths — the Metal pass still runs.
        let vm = LifeViewModel(api: MockLifeAPI())
        vm.updateRenderPath(
            accessibility: LifeAccessibilityEnvironment(reduceTransparency: true)
        )
        #expect(vm.currentRenderPath == .shader)
    }

    @Test
    func increaseContrastAloneKeepsShader() {
        let vm = LifeViewModel(api: MockLifeAPI())
        vm.updateRenderPath(
            accessibility: LifeAccessibilityEnvironment(increaseContrast: true)
        )
        #expect(vm.currentRenderPath == .shader)
    }

    @Test
    func togglingReduceMotionTogglesPath() {
        let vm = LifeViewModel(api: MockLifeAPI())
        vm.updateRenderPath(
            accessibility: LifeAccessibilityEnvironment(reduceMotion: true)
        )
        #expect(vm.currentRenderPath == .canvasFallback)
        vm.updateRenderPath(
            accessibility: LifeAccessibilityEnvironment(reduceMotion: false)
        )
        #expect(vm.currentRenderPath == .shader)
    }
}
