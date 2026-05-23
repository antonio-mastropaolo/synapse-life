import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Thin, non-allocating wrapper around UIKit feedback generators.
///
/// The generators are intentionally per-call rather than cached: the iOS
/// haptic engine spins up on first use of a generator, and the cost of
/// constructing one is negligible (≪1 ms) compared to the perceptible
/// difference between `.light` and `.selection` feedback at a moment that
/// must read as intentional. We do not call `prepare()` on cold-path
/// affordances (tab switches, pull-to-refresh completion) because the
/// 100-200 ms warm-up window is wider than the human-perceptible delay
/// from finger-down to haptic.
///
/// All call sites guard with `#if canImport(UIKit)` so the wrapper stays
/// inert when compiled into a unit test on a host without UIKit.
@MainActor
enum Haptics {

    /// Fired when the user changes the bottom tab.
    static func tabSwitch() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// Fired when a pull-to-refresh round-trip completes successfully.
    static func refreshComplete() {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }

    /// Fired when the user taps a drill-down row (account → detail, etc.).
    /// Subtle; we use `.soft` rather than `.medium` so it never competes
    /// with the system's own click feedback on the navigation push.
    static func drillDown() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        #endif
    }

    /// Fired when the user triggers a destructive or notable action via
    /// a swipe-action (Hide / Sync).
    static func swipeAction() {
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
