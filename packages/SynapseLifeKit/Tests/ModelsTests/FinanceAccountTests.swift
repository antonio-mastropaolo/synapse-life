import Foundation
import Testing
@testable import Models

/// Wire-level decoder tests for the finance accounts surface. The shape
/// here mirrors `/api/finance/accounts/route.ts` — Synapse v2 wraps an array
/// of `items` (link items) each carrying an array of `accounts`. The native
/// client flattens that into `FinanceAccount` rows because the iOS+macOS
/// surface lists accounts directly; the parent link-item metadata rides
/// along on the row for institution chips.
@Suite("FinanceAccount")
struct FinanceAccountTests {

    @Test
    func decodesServerAccountShape() throws {
        let json: [String: Any] = [
            "items": [
                [
                    "id": "item-1",
                    "provider": "plaid",
                    "institutionId": "ins_109511",
                    "institutionName": "Chase",
                    "itemStatus": "good",
                    "lastSyncAt": 1_739_625_600_000,
                    "lastSyncError": NSNull(),
                    "accounts": [
                        [
                            "id": "acc-cash",
                            "name": "Chase Checking",
                            "officialName": "Chase Total Checking",
                            "mask": "1234",
                            "type": "depository",
                            "subtype": "checking",
                            "currency": "USD",
                            "balance": [
                                "current": 12_345.67,
                                "available": 12_000.50,
                                "limit": NSNull(),
                                "capturedAt": 1_739_625_600_000
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder.synapseFinance.decode(FinanceAccountsResponse.self, from: data)
        #expect(response.accounts.count == 1)
        let account = try #require(response.accounts.first)
        #expect(account.id == "acc-cash")
        #expect(account.kind == .checking)
        #expect(account.institutionName == "Chase")
        #expect(account.mask == "1234")
        #expect(account.currency == "USD")
        // Decimal preserves the exact server value — no Double drift.
        #expect(account.currentBalance == Decimal(string: "12345.67"))
    }

    @Test
    func unknownAccountKindMapsToOther() throws {
        let json: [String: Any] = [
            "items": [[
                "id": "item-2",
                "provider": "plaid",
                "institutionId": NSNull(),
                "institutionName": NSNull(),
                "itemStatus": "good",
                "lastSyncAt": NSNull(),
                "lastSyncError": NSNull(),
                "accounts": [[
                    "id": "acc-future",
                    "name": "Unrecognized",
                    "officialName": NSNull(),
                    "mask": NSNull(),
                    "type": "future-asset-class",
                    "subtype": "crypto",
                    "currency": "usd",
                    "balance": [
                        "current": 1.0,
                        "available": NSNull(),
                        "limit": NSNull(),
                        "capturedAt": NSNull()
                    ]
                ]]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = try JSONDecoder.synapseFinance.decode(FinanceAccountsResponse.self, from: data)
        let account = try #require(response.accounts.first)
        #expect(account.kind == .other)
        // ISO 4217 normalization: lowercased server input is uppercased.
        #expect(account.currency == "USD")
    }

    @Test
    func liabilityKindsAreClassifiedAsLiabilities() {
        #expect(AccountKind.credit.isLiability)
        #expect(AccountKind.loan.isLiability)
        #expect(!AccountKind.checking.isLiability)
        #expect(!AccountKind.savings.isLiability)
        #expect(!AccountKind.brokerage.isLiability)
        #expect(!AccountKind.retirement.isLiability)
        #expect(!AccountKind.other.isLiability)
    }

    @Test
    func sendableHashableIdentifiable() {
        let a = FinanceAccount(
            id: "a", institutionId: nil, institutionName: nil,
            name: "A", officialName: nil, mask: nil,
            kind: .checking, currency: "USD",
            currentBalance: Decimal(100),
            availableBalance: nil, limitAmount: nil,
            balanceCapturedAt: nil
        )
        let b = a
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a.id == "a")
        // Compile-time check that FinanceAccount is Sendable: pass it to a
        // generic that requires Sendable.
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        _ = requireSendable(a)
    }

    @Test
    func plaidTypeSubtypePairMapsToNativeKind() {
        // The server today emits `type` + `subtype` separately. The native
        // mapper collapses the pair into the platform-friendly `AccountKind`
        // enum so the UI doesn't need to know about Plaid taxonomy.
        #expect(AccountKind.fromPlaid(type: "depository", subtype: "checking") == .checking)
        #expect(AccountKind.fromPlaid(type: "depository", subtype: "savings") == .savings)
        #expect(AccountKind.fromPlaid(type: "depository", subtype: nil) == .checking)
        #expect(AccountKind.fromPlaid(type: "credit", subtype: "credit card") == .credit)
        #expect(AccountKind.fromPlaid(type: "loan", subtype: "student") == .loan)
        #expect(AccountKind.fromPlaid(type: "investment", subtype: "brokerage") == .brokerage)
        #expect(AccountKind.fromPlaid(type: "investment", subtype: "401k") == .retirement)
        #expect(AccountKind.fromPlaid(type: "investment", subtype: "ira") == .retirement)
        #expect(AccountKind.fromPlaid(type: "investment", subtype: nil) == .brokerage)
        #expect(AccountKind.fromPlaid(type: "made-up", subtype: nil) == .other)
    }
}
