import Foundation
import Testing
@testable import AppLifecycle

@Suite("DeepLink routing")
struct DeepLinkRoutingTests {

    // Spotlight ---------------------------------------------------------

    @Test("synnapse://spotlight parses to .spotlight with nil query")
    func spotlightBare() throws {
        let url = try #require(URL(string: "synnapse://spotlight"))
        #expect(DeepLink.parse(url: url) == .spotlight(query: nil))
    }

    @Test("synnapse://spotlight?q=llm parses with query")
    func spotlightWithQuery() throws {
        let url = try #require(URL(string: "synnapse://spotlight?q=llm"))
        #expect(DeepLink.parse(url: url) == .spotlight(query: "llm"))
    }

    // Approvals ---------------------------------------------------------

    @Test("synnapse://approvals/12345 parses approvals with id")
    func approvalsById() throws {
        let url = try #require(URL(string: "synnapse://approvals/12345"))
        #expect(DeepLink.parse(url: url) == .approvals(id: "12345"))
    }

    @Test("synnapse://approvals parses approvals with nil id")
    func approvalsList() throws {
        let url = try #require(URL(string: "synnapse://approvals"))
        #expect(DeepLink.parse(url: url) == .approvals(id: nil))
    }

    // Finance -----------------------------------------------------------

    @Test("finance subroutes parse to typed surfaces")
    func financeSubroutes() throws {
        let cases: [(String, DeepLink.FinanceSurface)] = [
            ("synnapse://finance/personal", .personal),
            ("synnapse://finance/accounts", .accounts),
            ("synnapse://finance/transactions", .transactions),
            ("synnapse://finance/investments", .investments),
            ("synnapse://finance/work", .work)
        ]
        for (raw, surface) in cases {
            let url = try #require(URL(string: raw))
            #expect(DeepLink.parse(url: url) == .finance(surface))
        }
    }

    // Life --------------------------------------------------------------

    @Test("synnapse://life parses to .life")
    func life() throws {
        let url = try #require(URL(string: "synnapse://life"))
        #expect(DeepLink.parse(url: url) == .life)
    }

    // People / Inbox / Advisors / Sequences / Octagon / Settings -------

    @Test("scalar surfaces parse correctly")
    func scalarSurfaces() throws {
        let cases: [(String, DeepLink)] = [
            ("synnapse://people/abc", .people(id: "abc")),
            ("synnapse://people", .people(id: nil)),
            ("synnapse://inbox/m-42", .inbox(messageId: "m-42")),
            ("synnapse://inbox", .inbox(messageId: nil)),
            ("synnapse://advisors/aria", .advisors(id: "aria")),
            ("synnapse://advisors", .advisors(id: nil)),
            ("synnapse://sequences/seq-1", .sequences(id: "seq-1")),
            ("synnapse://sequences", .sequences(id: nil)),
            ("synnapse://octagon/NVDA", .octagon(vendor: "NVDA")),
            ("synnapse://octagon", .octagon(vendor: nil)),
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
            .spotlight(query: nil),
            .spotlight(query: "llm judge"),
            .approvals(id: nil),
            .approvals(id: "12345"),
            .finance(.personal),
            .finance(.accounts),
            .finance(.transactions),
            .finance(.investments),
            .finance(.work),
            .life,
            .people(id: nil),
            .people(id: "kira"),
            .inbox(messageId: nil),
            .inbox(messageId: "msg-7"),
            .advisors(id: nil),
            .advisors(id: "aria"),
            .sequences(id: nil),
            .sequences(id: "seq-9"),
            .octagon(vendor: nil),
            .octagon(vendor: "AAPL"),
            .settings
        ]
        for link in links {
            let url = link.url
            let parsed = DeepLink.parse(url: url)
            #expect(parsed == link, "round-trip failed for \(link) -> \(url)")
        }
    }

    // Unknown / malformed ----------------------------------------------

    @Test("foreign scheme returns nil")
    func foreignScheme() throws {
        let url = try #require(URL(string: "https://example.com/spotlight"))
        #expect(DeepLink.parse(url: url) == nil)
    }

    @Test("unknown host returns nil")
    func unknownHost() throws {
        let url = try #require(URL(string: "synnapse://nowhere"))
        #expect(DeepLink.parse(url: url) == nil)
    }
}
