import Foundation
import Testing
@testable import Models
@testable import Networking
@testable import Features

private func approvalsRouteBody(rows: Int) -> Data {
    let approvals: [[String: Any]] = (0..<rows).map { i in
        [
            "id": "ap-\(i)",
            "received_at": 1_739_625_600 + i * 86_400,
            "approver_name": "Jacqulyn Ledger",
            "approver_role": "admin-coordinator",
            "category": "ai-tools",
            "approval_type": "approved",
            "amount_mentioned": 100.0 + Double(i),
            "notes": NSNull(),
            "linked_receipt_id": NSNull(),
            "subject": "Re: Anthropic spend #\(i)",
            "sender_address": "jled@wm.edu"
        ]
    }
    let payload: [String: Any] = [
        "total": rows,
        "limit": 50,
        "offset": 0,
        "approvals": approvals
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private func receiptsRouteBody(rows: Int) -> Data {
    let receipts: [[String: Any]] = (0..<rows).map { i in
        [
            "id": "r-\(i)",
            "receivedAt": "2026-02-1\(i)",
            "vendor": "Anthropic",
            "amount": 50.0 + Double(i),
            "currency": "USD",
            "documentKind": "receipt",
            "approvalId": "ap-0",
            "accountEmail": "amastropaolo@wm.edu",
            "submissionStatus": "pending"
        ]
    }
    let payload: [String: Any] = ["total": rows, "receipts": receipts]
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

@Suite("ApprovalsRepository")
struct ApprovalsRepositoryTests {

    @Test
    func splitFetchStitchesApprovalsAndReceipts() async throws {
        let session = URLProtocolStub.makeSession { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/api/approvals") {
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json", "ETag": "\"a-v1\""],
                    body: approvalsRouteBody(rows: 2)
                ))
            }
            if path.hasSuffix("/api/receipts") {
                return .success(.init(
                    statusCode: 200,
                    headers: ["Content-Type": "application/json"],
                    body: receiptsRouteBody(rows: 3)
                ))
            }
            return .success(.init(statusCode: 404, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveApprovalsAPI(client: makeClient(session: session))
        let repo = ApprovalsRepository(api: api)
        try await repo.refresh()
        let bundle = await repo.bundle
        #expect(bundle.approvals.count == 2)
        #expect(bundle.receipts.count == 3)
        #expect(bundle.approvals.first?.id == "ap-0")
    }

    @Test
    func bundledShapeAlsoDecodes() async throws {
        let body: [String: Any] = [
            "approvals": [
                [
                    "id": "ap-bundled",
                    "received_at": 1_739_625_600,
                    "approver_name": "Jacqulyn Ledger",
                    "approver_role": "admin-coordinator",
                    "category": "ai-tools",
                    "approval_type": "pending",
                    "amount_mentioned": NSNull(),
                    "notes": NSNull(),
                    "linked_receipt_id": NSNull(),
                    "subject": "Bundled",
                    "sender_address": "jled@wm.edu"
                ]
            ],
            "receipts": [
                [
                    "id": "r-bundled",
                    "receivedAt": "2026-02-12",
                    "vendor": "Anthropic",
                    "amount": 99.0,
                    "currency": "USD",
                    "documentKind": "receipt",
                    "approvalId": "ap-bundled",
                    "accountEmail": "amastropaolo@wm.edu",
                    "submissionStatus": "pending"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.hasSuffix("/api/approvals/bundle") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json", "ETag": "\"b-1\""],
                body: data
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveApprovalsAPI(client: makeClient(session: session), preferBundled: true)
        let repo = ApprovalsRepository(api: api)
        try await repo.refresh()
        let bundle = await repo.bundle
        #expect(bundle.approvals.count == 1)
        #expect(bundle.approvals.first?.id == "ap-bundled")
        #expect(bundle.receipts.count == 1)
    }

    @Test
    func cacheSurvives304() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { request in
            let n = counter.next()
            let path = request.url?.path ?? ""
            if path.hasSuffix("/api/approvals") {
                if n <= 2 {
                    return .success(.init(
                        statusCode: 200,
                        headers: ["Content-Type": "application/json", "ETag": "\"a-1\""],
                        body: approvalsRouteBody(rows: 1)
                    ))
                }
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"a-1\"")
                return .success(.init(statusCode: 304, headers: [:], body: Data()))
            }
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: receiptsRouteBody(rows: 1)
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }

        let api = LiveApprovalsAPI(client: makeClient(session: session))
        let repo = ApprovalsRepository(api: api)
        try await repo.refresh()
        let firstBundle = await repo.bundle
        #expect(firstBundle.approvals.count == 1)
        // Second refresh: server sends 304 for approvals.
        try await repo.refresh()
        let secondBundle = await repo.bundle
        // 304 path returns no bundle — repository preserves the cached one.
        #expect(secondBundle.approvals.count == 1)
        #expect(secondBundle.approvals.first?.id == firstBundle.approvals.first?.id)
    }

    @Test
    func refreshReplacesPriorCache() async throws {
        let mock = MockApprovalsAPI()
        let initial = ApprovalsBundle(
            approvals: [
                Approval(
                    id: "a1", title: "first", vendor: nil, approver: "j",
                    approverRole: "admin-coordinator", category: "ai-tools",
                    requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    validUntil: nil, status: .pending,
                    workdayURL: nil, totalAmount: nil, currency: nil
                )
            ],
            receipts: []
        )
        await mock.setNextBundle(initial)
        let repo = ApprovalsRepository(api: mock)
        try await repo.refresh()
        #expect(await repo.bundle.approvals.first?.id == "a1")

        let next = ApprovalsBundle(
            approvals: [
                Approval(
                    id: "a2", title: "second", vendor: nil, approver: "j",
                    approverRole: "admin-coordinator", category: "ai-tools",
                    requestedAt: Date(timeIntervalSince1970: 1_710_000_000),
                    validUntil: nil, status: .approved,
                    workdayURL: nil, totalAmount: nil, currency: nil
                )
            ],
            receipts: []
        )
        await mock.setNextBundle(next)
        try await repo.refresh()
        #expect(await repo.bundle.approvals.first?.id == "a2")
    }
}
