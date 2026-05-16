import Foundation
import Testing
@testable import Models
@testable import Networking

private func briefBody(vendor: String) -> Data {
    let payload: [String: Any] = [
        "ok": true,
        "cached": true,
        "capturedAt": 1_715_798_400_000,
        "brief": [
            "vendor": vendor,
            "legalName": "\(vendor), PBC",
            "status": "private",
            "yearFounded": 2021,
            "employees": 800,
            "hq": ["city": "San Francisco", "stateProvince": "CA", "country": "US"],
            "primaryIndustry": "AI / ML",
            "verticals": ["enterprise"],
            "competitors": ["OpenAI", "Cohere"],
            "lastValuationUsd": 18400.0,
            "lastValuationAt": "2024-03-26",
            "lastFinancing": ["type": "Series C", "sizeUsd": 750.0, "asOf": "2024-03-26"],
            "vcRaisedUsd": 7900.0,
            "revenueUsd": 850.0,
            "ceo": ["name": "Dario Amodei", "email": NSNull()],
            "octagonUpdatedAt": "2025-01-15"
        ]
    ]
    return try! JSONSerialization.data(withJSONObject: payload)
}

private func membershipsBody() -> Data {
    let payload: [String: Any] = [
        "memberships": [
            [
                "id": "m_001",
                "vendor": "Netflix",
                "averageAmount": 15.49,
                "cadence": "monthly",
                "nextPredictedAt": "2026-06-04",
                "lastSeenAt": "2026-05-04",
                "confidence": 0.97,
                "status": "active"
            ]
        ],
        "nextCursor": NSNull()
    ]
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

@Suite("OctagonRepository")
struct OctagonRepositoryTests {

    @Test
    func briefDecodesAndUrlEncodesVendorName() async throws {
        let session = URLProtocolStub.makeSession { request in
            // "Whole Foods" should be percent-encoded inside the path.
            let path = request.url?.path ?? ""
            #expect(path.contains("Whole%20Foods"))
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: briefBody(vendor: "Whole Foods")
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveOctagonAPI(client: makeClient(session: session))
        let brief = try await api.brief(vendor: "Whole Foods")
        #expect(brief.vendor == "Whole Foods")
        #expect(brief.competitors.count == 2)
        #expect(brief.lastValuationUsdM == Decimal(string: "18400.0"))
    }

    @Test
    func briefSurfacesOkFalseAsServerError() async throws {
        let body = try! JSONSerialization.data(withJSONObject: [
            "ok": false,
            "error": "octagon unavailable",
            "brief": [
                "vendor": "x",
                "hq": ["city": NSNull(), "stateProvince": NSNull(), "country": NSNull()]
            ]
        ])
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: body
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveOctagonAPI(client: makeClient(session: session))
        do {
            _ = try await api.brief(vendor: "x")
            Issue.record("expected throw")
        } catch let APIError.server(status) {
            #expect(status == 500)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test
    func membershipsContractGateReturnsEmptyWithoutHittingServer() async throws {
        let counter = AtomicInt()
        let session = URLProtocolStub.makeSession { _ in
            _ = counter.next()
            return .success(.init(statusCode: 200, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveOctagonAPI(
            client: makeClient(session: session),
            membershipsContractLive: false
        )
        let result = try await api.memberships(cursor: nil)
        #expect(result.memberships.isEmpty)
        #expect(result.nextCursor == nil)
        #expect(counter.value == 0)
    }

    @Test
    func membershipsContractLiveDecodesPayload() async throws {
        let session = URLProtocolStub.makeSession { request in
            #expect(request.url?.path.hasSuffix("/api/finance/memberships") == true)
            return .success(.init(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: membershipsBody()
            ))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveOctagonAPI(
            client: makeClient(session: session),
            membershipsContractLive: true
        )
        let result = try await api.memberships(cursor: nil)
        #expect(result.memberships.count == 1)
        #expect(result.memberships[0].vendor == "Netflix")
    }

    @Test
    func membershipsTolerates404FromForwardCompatGate() async throws {
        let session = URLProtocolStub.makeSession { _ in
            .success(.init(statusCode: 404, headers: [:], body: Data()))
        }
        defer { URLProtocolStub.releaseSession(session) }
        let api = LiveOctagonAPI(
            client: makeClient(session: session),
            membershipsContractLive: true
        )
        let result = try await api.memberships(cursor: nil)
        #expect(result.memberships.isEmpty)
    }
}
