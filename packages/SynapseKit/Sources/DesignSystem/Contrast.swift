import Foundation

/// WCAG 2.1 relative-luminance contrast ratio. Inputs are sRGB components in
/// [0,1]. We compute on raw `ColorToken` rather than `SwiftUI.Color` because
/// pulling components back out of a `Color` is platform-dependent and lossy.
public func contrastRatio(_ a: ColorToken, _ b: ColorToken) -> Double {
    let la = relativeLuminance(a)
    let lb = relativeLuminance(b)
    let lighter = max(la, lb)
    let darker  = min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)
}

private func relativeLuminance(_ token: ColorToken) -> Double {
    let r = channelLuminance(token.red)
    let g = channelLuminance(token.green)
    let b = channelLuminance(token.blue)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

private func channelLuminance(_ component: Double) -> Double {
    if component <= 0.03928 {
        return component / 12.92
    }
    return pow((component + 0.055) / 1.055, 2.4)
}
