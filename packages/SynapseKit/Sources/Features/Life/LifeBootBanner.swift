import Foundation
import CoreGraphics

/// Generator for the LIFE terminal boot banner.
///
/// The banner is the first thing the user sees on the LIFE pane. It must
/// render correctly even when the entry buffer is empty and the server
/// contract (`/api/life/entries`) is not yet live in synapse-v2. Pure: the
/// same inputs always produce the same line set, so we can lock the exact
/// shape in tests and treat the banner as a deterministic UI surface.
public enum LifeBootBanner {

    /// Produce the multi-line boot banner.
    ///
    /// Line layout (4 lines, always):
    ///   1. `SYNAPSE LIFE v<version>`
    ///   2. `amber phosphor terminal · <W>x<H> · <hz>hz`
    ///   3. `loaded <N> entries from /api/life/entries`
    ///   4. when `serverContractLive == true && entryCount > 0`:
    ///        `feed online — streaming`
    ///      otherwise:
    ///        `awaiting entries...`
    ///
    /// Viewport dimensions round to the nearest integer — fractional
    /// logical sizes (from Retina backing stores) must not bleed into the
    /// banner.
    public static func lines(
        version: String,
        viewport: CGSize,
        refreshHz: Int,
        entryCount: Int,
        serverContractLive: Bool
    ) -> [String] {
        let w = Int(viewport.width.rounded())
        let h = Int(viewport.height.rounded())
        let closing: String
        if serverContractLive, entryCount > 0 {
            closing = "feed online — streaming"
        } else {
            closing = "awaiting entries..."
        }
        return [
            "SYNAPSE LIFE v\(version)",
            "amber phosphor terminal · \(w)x\(h) · \(refreshHz)hz",
            "loaded \(entryCount) entries from /api/life/entries",
            closing
        ]
    }

    /// Footer line painted at the bottom of the buffer when the feed is
    /// known to be unwired server-side. Single line of dim phosphor.
    public static let unwiredFooter: String =
        "// no entries yet — the LIFE pipeline is not wired in synapse-v2 server"

    /// Current product version. Bumped manually when the LIFE pane ships a
    /// meaningful behavior change. Tests pin the exact string so a version
    /// bump is a deliberate edit.
    public static let currentVersion: String = "0.1.0"
}
