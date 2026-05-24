import Foundation
import Testing
@testable import Connectors
@testable import Models
@testable import Networking

/// Exercises the real `APIClient.send` path of `LivePlaidConnector` against a
/// stubbed transport. The synapse-v2 proxy endpoints are server-side work; this
/// suite pins the iOS-side contract — request path, method, envelope decoding,
/// and error mapping — so the connector goes live the moment the routes land.
@Suite("LivePlaidConnector")
struct LivePlaidConnectorTests {

    /// Builds a connector whose transport answers from `handler`. The base URL
    /// has a trailing slash so relative endpoint paths compose cleanly.
    private func makeConnector(
        _ handler: @escaping URLProtocolStub.Handler
    ) -> (LivePlaidConnector, URLSession) {
        let session = URLProtocolStub.makeSession(handler)
        let client = APIClient(
            baseURL: URL(string: "https://api.test/")!,
            session: session,
            retry: .none
        )
        return (LivePlaidConnector(client: client, environment: .sandbox), session)
    }

    private func ok(_ json: String) -> Result<URLProtocolStub.Response, Error> {
        .success(.init(statusCode: 200, body: Data(json.utf8)))
    }

    @Test
    func createLinkTokenDecodesTokenAndEpochExpiration() async throws {
        let (connector, session) = makeConnector { _ in
            self.ok(#"{"linkToken":"link-sandbox-abc","expiration":1730000000}"#)
        }
        defer { URLProtocolStub.releaseSession(session) }

        let token = try await connector.createLinkToken(userId: "user-1")
        #expect(token.token == "link-sandbox-abc")
        #expect(token.expiration == Date(timeIntervalSince1970: 1_730_000_000))

        let recorded = URLProtocolStub.requests(for: session)
        #expect(recorded.count == 1)
        #expect(recorded.first?.httpMethod == "POST")
        #expect(recorded.first?.url?.path == "/api/connectors/plaid/link-token/create")
    }

    @Test
    func createLinkTokenAcceptsIso8601Expiration() async throws {
        let (connector, session) = makeConnector { _ in
            self.ok(#"{"linkToken":"link-1","expiration":"2026-04-01T00:00:00Z"}"#)
        }
        defer { URLProtocolStub.releaseSession(session) }

        let token = try await connector.createLinkToken(userId: "user-1")
        let expected = ISO8601DateFormatter().date(from: "2026-04-01T00:00:00Z")
        #expect(token.expiration == expected)
    }

    @Test
    func exchangePublicTokenReturnsRefNeverRawToken() async throws {
        let (connector, session) = makeConnector { _ in
            self.ok(#"""
            {"itemId":"item-9","institutionId":"ins_1","institutionName":"Test Bank","accessTokenRef":"kc:ref-9"}
            """#)
        }
        defer { URLProtocolStub.releaseSession(session) }

        let item = try await connector.exchangePublicToken("public-sandbox-xyz")
        #expect(item.id == "item-9")
        #expect(item.institutionId == "ins_1")
        #expect(item.institutionName == "Test Bank")
        #expect(item.accessTokenRef == "kc:ref-9")
        #expect(!item.accessTokenRef.contains("public-sandbox"))

        let path = URLProtocolStub.requests(for: session).first?.url?.path
        #expect(path == "/api/connectors/plaid/item/public-token/exchange")
    }

    @Test
    func syncTransactionsProjectsDeltaWithSignAndRemovedIds() async throws {
        let (connector, session) = makeConnector { _ in
            self.ok(#"""
            {
              "added":[{"id":"t1","accountId":"a1","amount":-12.5,"currency":"usd","date":"2026-04-01","name":"Coffee","category":"Food and Drink","pending":false}],
              "modified":[{"id":"t0","accountId":"a1","amount":42.0,"currency":"usd","date":"2026-03-30","name":"Refund","category":null,"pending":true}],
              "removed":["t-removed"],
              "nextCursor":"cursor-2",
              "hasMore":false
            }
            """#)
        }
        defer { URLProtocolStub.releaseSession(session) }

        let delta = try await connector.syncTransactions(itemId: "item-9", cursor: nil)
        #expect(delta.added.count == 1)
        #expect(delta.added.first?.amount == Decimal(string: "-12.5"))
        #expect(delta.added.first?.category == .knownCategory("Food and Drink"))
        #expect(delta.modified.count == 1)
        #expect(delta.modified.first?.category == .unknown)
        #expect(delta.removedIds == ["t-removed"])
        #expect(delta.nextCursor == "cursor-2")
        #expect(delta.hasMore == false)

        let path = URLProtocolStub.requests(for: session).first?.url?.path
        #expect(path == "/api/connectors/plaid/transactions/sync")
    }

    @Test
    func fetchAccountsFlattensItemEnvelope() async throws {
        let (connector, session) = makeConnector { _ in
            self.ok(#"""
            {"items":[{"id":"item-9","institutionId":"ins_1","institutionName":"Test Bank","accounts":[
              {"id":"a1","name":"Everyday Checking","type":"depository","subtype":"checking","currency":"usd","balance":{"current":1234.56}},
              {"id":"a2","name":"Rewards Card","type":"credit","subtype":"credit card","currency":"usd","balance":{"current":250.0,"limit":2000.0}}
            ]}]}
            """#)
        }
        defer { URLProtocolStub.releaseSession(session) }

        let accounts = try await connector.fetchAccounts(itemId: "item-9")
        #expect(accounts.count == 2)
        #expect(accounts.contains { $0.kind == .checking })
        let credit = try #require(accounts.first { $0.kind == .credit })
        #expect(credit.kind.isLiability)
        #expect(credit.limitAmount == Decimal(string: "2000"))
        #expect(credit.institutionName == "Test Bank")

        let path = URLProtocolStub.requests(for: session).first?.url?.path
        #expect(path == "/api/connectors/plaid/accounts/get")
    }

    @Test
    func fetchInvestmentsProjectsHoldings() async throws {
        let (connector, session) = makeConnector { _ in
            self.ok(#"""
            {"holdings":[
              {"accountId":"a1","accountName":"Brokerage","securityId":"s1","ticker":"AAPL","name":"Apple Inc","type":"equity","quantity":10,"price":195,"value":1950,"currency":"usd"},
              {"accountId":"a1","accountName":"Brokerage","securityId":"s2","ticker":"VOO","name":"Vanguard S&P 500","type":"etf","quantity":2,"price":500,"value":1000,"currency":"usd"}
            ]}
            """#)
        }
        defer { URLProtocolStub.releaseSession(session) }

        let positions = try await connector.fetchInvestments(itemId: "item-9")
        #expect(positions.count == 2)
        let aapl = try #require(positions.first { $0.ticker == "AAPL" })
        #expect(aapl.kind == .stock)
        #expect(aapl.value == Decimal(string: "1950"))
        let voo = try #require(positions.first { $0.ticker == "VOO" })
        #expect(voo.kind == .etf)

        let path = URLProtocolStub.requests(for: session).first?.url?.path
        #expect(path == "/api/connectors/plaid/investments/get")
    }

    @Test
    func removeItemAcceptsEmptyBody() async throws {
        let (connector, session) = makeConnector { _ in self.ok("{}") }
        defer { URLProtocolStub.releaseSession(session) }

        try await connector.removeItem(itemId: "item-9")
        let path = URLProtocolStub.requests(for: session).first?.url?.path
        #expect(path == "/api/connectors/plaid/item/remove")
    }

    @Test
    func serverErrorMapsToServerStatus() async throws {
        let (connector, session) = makeConnector { _ in
            .success(.init(statusCode: 503, body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        await #expect(throws: PlaidConnectorError.server(status: 503)) {
            _ = try await connector.fetchAccounts(itemId: "item-9")
        }
    }

    @Test
    func malformedBodyMapsToDecodingError() async throws {
        let (connector, session) = makeConnector { _ in
            self.ok(#"{"unexpected":true}"#)
        }
        defer { URLProtocolStub.releaseSession(session) }

        await #expect(throws: PlaidConnectorError.decoding) {
            _ = try await connector.createLinkToken(userId: "user-1")
        }
    }
}
