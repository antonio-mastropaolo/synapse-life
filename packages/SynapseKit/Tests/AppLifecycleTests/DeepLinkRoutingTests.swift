import Foundation
import Testing
@testable import AppLifecycle

@Suite("DeepLink routing")
struct DeepLinkRoutingTests {

    // Finance -----------------------------------------------------------

    @Test("finance subroutes parse to typed surfaces")
    func financeSubroutes() throws {
        let cases: [(String, DeepLink.FinanceSurface)] = [
            ("synapse://finance/personal", .personal),
            ("synapse://finance/accounts", .accounts),
            ("synapse://finance/transactions", .transactions),
            ("synapse://finance/investments", .investments)
        ]
        for (raw, surface) in cases {
            let url = try #require(URL(string: raw))
            #expect(DeepLink.parse(url: url) == .finance(surface))
        }
    }

    @Test("finance/work is rejected — synapse-v2 work scope is not in Synapse")
    func financeWorkRejected() throws {
        let url = try #require(URL(string: "synapse://finance/work"))
        #expect(DeepLink.parse(url: url) == nil)
    }

    // Life --------------------------------------------------------------

    @Test("synapse://life parses to .life")
    func life() throws {
        let url = try #require(URL(string: "synapse://life"))
        #expect(DeepLink.parse(url: url) == .life)
    }

    // Advisors / Settings ----------------------------------------------

    @Test("scalar surfaces parse correctly")
    func scalarSurfaces() throws {
        let cases: [(String, DeepLink)] = [
            ("synapse://advisors/aria", .advisors(id: "aria")),
            ("synapse://advisors", .advisors(id: nil)),
            ("synapse://settings", .settings)
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
    // re-introducing them lights up the suite. Synapse never carries
    // synapse-v2 work surfaces; those live in the web client only.

    @Test("removed work hosts return nil")
    func workHostsRejected() throws {
        let raws = [
            "synapse://spotlight",
            "synapse://spotlight?q=llm",
            "synapse://approvals",
            "synapse://approvals/12345",
            "synapse://people",
            "synapse://people/abc",
            "synapse://inbox",
            "synapse://inbox/m-42",
            "synapse://sequences",
            "synapse://sequences/seq-1",
            "synapse://octagon",
            "synapse://octagon/NVDA"
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
        let url = try #require(URL(string: "synapse://nowhere"))
        #expect(DeepLink.parse(url: url) == nil)
    }
}
