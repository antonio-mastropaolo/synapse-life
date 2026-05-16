import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func accountsBody(rows: Int) -> Data {
    let accounts: [[String: Any]] = (0..<rows).map { i in
        [
            "id": "acc-\(i)",
            "name": "Account \(i)",
            "officialName": NSNull(),
            "mask": "00\(i)",
            "type": "depository",
            "subtype": "checking",
            "currency": "USD",
            "balance": [
                "current": 1_000.0 + Double(i),
                "available": NSNull(),
                "limit": NSNull(),
                "capturedAt": NSNull()
            ]
        ]
    }
    let payload: [String: Any] = [
        "items": [[
            "id": "item-1",
            "provider": "plaid",
            "institutionId": "ins_x",
            "institutionName": "Test Bank",
            "itemStatus": "good",
            "lastSyncAt": NSNull(),
            "lastSyncError": NSNull(),
            "accounts": accounts
        ]]
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private func transactionsBody(rows: Int, idPrefix: String = "txn", nextCursor: String? = nil) -> Data {
    let txns: [[String: Any]] = (0..<rows).map { i in
        [
            "id": "\(idPrefix)-\(i)",
            "source": "bank",
            "accountId": "acc-0",
            "accountName": "Account 0",
            "amount": -10.0 - Double(i),
            "currency": "USD",
            "date": "2026-04-1\(i % 10)",
            "name": "Vendor \(i)",
            "merchantName": NSNull(),
            "category": "Food & Drink",
            "subcategory": NSNull(),
            "pending": false
        ]
    }
    var payload: [String: Any] = ["rows": txns, "count": rows]
    if let nextCursor { payload["nextCursor"] = nextCursor }
    return try! JSONSerialization.data(withJSONObject: payload)
}

private func makeClient(session: URLSession) -> APIClient {
    APIClient(
        baseURL: URL(string: "https://api.synnapse.test/v1/")!,
        session: session,
        defaultHeaders: ["Accept": "application/json"],
        auth: nil,
        retry: .none
    )
}

@Suite("FinanceRepository")
struct FinanceRepositoryTests {

    @Test
    func accountsListDecodesAndPopulatesRepository() async throws {
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.hasSuffix("/api/finance/accounts") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json", "ETag": "\"acc-v1\""],
                body: accountsBody(rows: 3)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveFinanceAPI(client: makeClient(session: session))
        let repo = FinanceRepository(api: api)
        try await repo.refreshAccounts()
        let accounts = await repo.accounts
        #expect(accounts.count == 3)
        #expect(accounts.first?.id == "acc-0")
        #expect(accounts.first?.institutionName == "Test Bank")
    }

    @Test
    func accountsCacheSurvives304() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            if n == 1 {
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json", "ETag": "\"acc-v1\""],
                    body: accountsBody(rows: 2)
                ))
            }
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"acc-v1\"")
            return .success(.init(statusCode: 304, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveFinanceAPI(client: makeClient(session: session))
        let repo = FinanceRepository(api: api)
        try await repo.refreshAccounts()
        let before = await repo.accounts.map(\.id)
        try await repo.refreshAccounts()
        let after = await repo.accounts.map(\.id)
        // 304 → cached rows survive intact.
        #expect(before == after)
        #expect(after.count == 2)
    }

    @Test
    func transactionsPaginationFollowsCursor() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            if n == 1 {
                #expect(request.url?.query?.contains("cursor=") != true)
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: transactionsBody(rows: 2, idPrefix: "p1", nextCursor: "c2")
                ))
            }
            #expect(request.url?.query?.contains("cursor=c2") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: transactionsBody(rows: 2, idPrefix: "p2")
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveFinanceAPI(client: makeClient(session: session))
        let repo = FinanceRepository(api: api)
        try await repo.refreshTransactions()
        try await repo.loadMoreTransactions()
        let ids = await repo.transactions.map(\.id)
        #expect(ids == ["p1-0", "p1-1", "p2-0", "p2-1"])
    }

    @Test
    func transactionsStopsWhenServerHasNoCursor() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { _ in
            _ = counter.next()
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: transactionsBody(rows: 1)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveFinanceAPI(client: makeClient(session: session))
        let repo = FinanceRepository(api: api)
        try await repo.refreshTransactions()
        try await repo.loadMoreTransactions()
        try await repo.loadMoreTransactions()
        #expect(counter.value == 1)
    }

    @Test
    func perAccountTransactionsPassesAccountIdAsQuery() async throws {
        let lastURL = AtomicString()
        let session = URLProtocolStub.makeSession { request in
            lastURL.set(request.url?.absoluteString ?? "")
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: transactionsBody(rows: 0)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveFinanceAPI(client: makeClient(session: session))
        let repo = FinanceRepository(api: api)
        try await repo.refreshTransactions(accountId: "acc-cash")
        #expect(lastURL.value.contains("accountId=acc-cash"))
    }
}
