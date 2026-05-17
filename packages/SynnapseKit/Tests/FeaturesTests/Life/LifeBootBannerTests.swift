import Foundation
import Testing
@testable import Features

/// `LifeBootBanner` is a pure generator. Every input — version, viewport,
/// entry count, server-contract flag — fully determines the output. The
/// banner is the first thing the user sees on the LIFE pane and has to
/// render correctly even when `/api/life/entries` is missing, so we lock
/// the exact line shapes here.
@Suite("LifeBootBanner")
struct LifeBootBannerTests {

    @Test
    func bannerEmitsFourLinesForZeroEntries() {
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1280, height: 800),
            refreshHz: 60,
            entryCount: 0,
            serverContractLive: false
        )
        #expect(banner.count == 4)
    }

    @Test
    func firstLineCarriesProductNameAndVersion() {
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1280, height: 800),
            refreshHz: 60,
            entryCount: 0,
            serverContractLive: false
        )
        // First line is the masthead. Title-cased product name + version.
        #expect(banner[0] == "SYNAPSE LIFE v0.1.0")
    }

    @Test
    func secondLineDescribesViewportAndRefresh() {
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1280, height: 800),
            refreshHz: 60,
            entryCount: 0,
            serverContractLive: false
        )
        // "amber phosphor terminal · WxH · Nhz" — integer dims, lowercase.
        #expect(banner[1] == "amber phosphor terminal · 1280x800 · 60hz")
    }

    @Test
    func thirdLineReportsLoadCountAndEndpoint() {
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1280, height: 800),
            refreshHz: 60,
            entryCount: 0,
            serverContractLive: false
        )
        #expect(banner[2] == "loaded 0 entries from /api/life/entries")
    }

    @Test
    func fourthLineWaitsForEntriesWhenEmpty() {
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1280, height: 800),
            refreshHz: 60,
            entryCount: 0,
            serverContractLive: false
        )
        #expect(banner[3] == "awaiting entries...")
    }

    @Test
    func fourthLineShowsFeedOnlineWhenEntriesPresent() {
        // When the entry buffer is non-empty, the closing banner line
        // shifts from "awaiting" to a feed-online confirmation so the
        // terminal reads as connected rather than waiting.
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1280, height: 800),
            refreshHz: 60,
            entryCount: 7,
            serverContractLive: true
        )
        #expect(banner[2] == "loaded 7 entries from /api/life/entries")
        #expect(banner[3] == "feed online — streaming")
    }

    @Test
    func viewportDimensionsRoundToIntegers() {
        // Fractional layout sizes (Retina-adjacent) must not bleed into
        // the banner. We render the visible logical viewport, not the
        // backing-store pixel buffer.
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1279.6, height: 799.4),
            refreshHz: 60,
            entryCount: 0,
            serverContractLive: false
        )
        #expect(banner[1].contains("1280x799"))
    }

    @Test
    func serverContractFalseMarksFeedOffline() {
        // When the server-side route is not live (the current synapse-v2
        // state), even a non-zero buffer (from injected snapshot data)
        // should still read "awaiting" — we don't want to lie about the
        // feed.
        let banner = LifeBootBanner.lines(
            version: "0.1.0",
            viewport: CGSize(width: 1280, height: 800),
            refreshHz: 60,
            entryCount: 3,
            serverContractLive: false
        )
        #expect(banner[3] == "awaiting entries...")
    }
}
