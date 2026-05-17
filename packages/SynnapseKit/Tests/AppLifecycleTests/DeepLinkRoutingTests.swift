import Foundation
import Testing
@testable import AppLifecycle

@Suite("DeepLink routing")
struct DeepLinkRoutingTests {

    // Finance -----------------------------------------------------------

    @Test("finance subroutes parse to typed surfaces")
    func financeSubroutes() throws {
        let cases: [(String, DeepLink.FinanceSurface)] = [
            ("synnapse://finance/personal", .personal),
            ("synnapse://finance/accounts", .accounts),
            ("synnapse://finance/transactions", .transactions),
            ("synnapse://finance/investments", .investments)
        ]
        for (raw, surface) in cases {
            let url = try #require(URL(string: raw))
            #expect(DeepLink.parse(url: url) == .finance(surface))
        }
    }

    @Test("finance/work is rejected — synapse-v2 work scope is not in Synnapse")
    func financeWorkRejected() throws {
        let url = try #require(URL(string: "synnapse://finance/work"))
        #expect(DeepLink.parse(url: url) == nil)
    }

    // Life --------------------------------------------------------------

    @Test("synnapse://life parses to .life")
    func life() throws {
        let url = try #require(URL(string: "synnapse://life"))
        #expect(DeepLink.parse(url: url) == .life)
    }

    // Advisors / Settings ----------------------------------------------

    @Test("scalar surfaces parse correctly")
    func scalarSurfaces() throws {
        let cases: [(String, DeepLink)] = [
            ("synnapse://advisors/aria", .advisors(id: "aria")),
            ("synnapse://advisors", .advisors(id: nil)),
            ("synnapse://settings", .settings)
        ]
        for (raw, link) in cases {
            let url = try #require(URL(string: raw))
            #expect(DeepLink.parse(url: url) == link, "expected \(raw) to parse to \(link)")
        }
    }

    // Round-trip --------------------------------------------------------

    @Test("every link round-trips through url and parse")
    func roundTrip() throws {
        let links: [DeepLink] = [
            .finance(.personal),
            .finance(.accounts),
            .finance(.transactions),
            .finance(.investments),
            .life,
            .advisors(id: nil),
            .advisors(id: "aria"),
            .settings
        ]
        for link in links {
            let url = link.url
            let parsed = DeepLink.parse(url: url)
            #expect(parsed == link, "round-trip failed for \(link) -> \(url)")
        }
    }

    // Removed work surfaces — assert they parse to nil so a regression
    // re-introducing them lights up the suite. Synnapse never carries
    // synapse-v2 work surfaces; those live in the web client only.

    @Test("removed work hosts return nil")
    func workHostsRejected() throws {
        let raws = [
            "synnapse://spotlight",
            "synnapse://spotlight?q=llm",
            "synnapse://approvals",
            "synnapse://approvals/12345",
            "synnapse://people",
            "synnapse://people/abc",
            "synnapse://inbox",
            "synnapse://inbox/m-42",
            "synnapse://sequences",
            "synnapse://sequences/seq-1",
            "synnapse://octagon",
            "synnapse://octagon/NVDA"
        ]
        for raw in raws {
            let url = try #require(URL(string: raw))
            #expect(DeepLink.parse(url: url) == nil, "expected \(raw) to be rejected")
        }
    }

    // Unknown / malformed ----------------------------------------------

    @Test("foreign scheme returns nil")
    func foreignScheme() throws {
        let url = try #require(URL(string: "https://example.com/finance"))
        #expect(DeepLink.parse(url: url) == nil)
    }

    @Test("unknown host returns nil")
    func unknownHost() throws {
        let url = try #require(URL(string: "synnapse://nowhere"))
        #expect(DeepLink.parse(url: url) == nil)
    }
}
