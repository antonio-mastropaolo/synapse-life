import Foundation
import Testing
@testable import Models

@Suite("Approval / Receipt / DocumentKind / ApprovalStatus decoding")
struct ApprovalTests {

    // MARK: - Approval

    @Test
    func approvalDecodesFromNativeShape() throws {
        let json = """
        {
          "id": "ap-1",
          "title": "Anthropic API spend (Jan-Apr 2026)",
          "vendor": "Anthropic",
          "approver": "Jacqulyn Ledger",
          "approverRole": "admin-coordinator",
          "category": "ai-tools",
          "requestedAt": "2026-02-15T14:00:00Z",
          "validUntil": "2027-02-15T14:00:00Z",
          "status": "approved",
          "workdayURL": "https://wd5.myworkday.com/wm/d/inst/12345/expense",
          "totalAmount": 412.55,
          "currency": "USD"
        }
        """.data(using: .utf8)!

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let approval = try dec.decode(Approval.self, from: json)
        #expect(approval.id == "ap-1")
        #expect(approval.status == .approved)
        #expect(approval.workdayURL?.host == "wd5.myworkday.com")
        #expect(approval.totalAmount == Decimal(string: "412.55"))
        #expect(approval.currency == "USD")
    }

    @Test
    func approvalProjectsFromServerRow() {
        let row = ServerApprovalRow(
            id: "ap-srv-1",
            received_at: 1_739_625_600, // 2026-02-15 14:00 UTC
            approver_name: "Jacqulyn Ledger",
            approver_role: "admin-coordinator",
            category: "ai-tools",
            approval_type: "approved",
            amount_mentioned: 412.55,
            notes: nil,
            linked_receipt_id: nil,
            subject: "Re: Anthropic API spend",
            sender_address: "jled@wm.edu"
        )
        let approval = Approval.fromServerRow(row)
        #expect(approval.id == "ap-srv-1")
        #expect(approval.status == .approved)
        #expect(approval.title == "Re: Anthropic API spend")
        // 1y validity window — see memory project_approval_detection.
        let oneYear: TimeInterval = 365 * 24 * 60 * 60
        let expected = Date(timeIntervalSince1970: 1_739_625_600 + oneYear)
        #expect(approval.validUntil?.timeIntervalSince1970 == expected.timeIntervalSince1970)
    }

    @Test
    func approvalIsSendableAndHashable() {
        let a = Approval(
            id: "x",
            title: "t",
            vendor: nil,
            approver: "j",
            approverRole: "admin-coordinator",
            category: "other",
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
            validUntil: nil,
            status: .pending,
            workdayURL: nil,
            totalAmount: nil,
            currency: nil
        )
        let b = a
        var set = Set<Approval>()
        set.insert(a); set.insert(b)
        #expect(set.count == 1)
    }

    // MARK: - Receipt + DocumentKind

    @Test
    func documentKindCases() {
        #expect(DocumentKind.receipt.isBundleable)
        #expect(!DocumentKind.invoice.isBundleable)
        #expect(!DocumentKind.refund.isBundleable)
        #expect(!DocumentKind.unknown.isBundleable)
    }

    @Test
    func receiptDecodesAndOnlyReceiptKindIsBundleable() throws {
        let json = """
        [
          {
            "id": "r1", "approvalId": "ap-1", "vendor": "Anthropic",
            "amount": 200.0, "currency": "USD",
            "date": "2026-02-10",
            "documentKind": "receipt", "sourceAccount": "amastropaolo@wm.edu",
            "submissionStatus": "pending"
          },
          {
            "id": "r2", "approvalId": "ap-1", "vendor": "Anthropic",
            "amount": 200.0, "currency": "USD",
            "date": "2026-02-10",
            "documentKind": "invoice", "sourceAccount": "amastropaolo@wm.edu",
            "submissionStatus": "skipped"
          }
        ]
        """.data(using: .utf8)!
        let receipts = try JSONDecoder().decode([Receipt].self, from: json)
        #expect(receipts.count == 2)
        #expect(receipts[0].documentKind == .receipt)
        #expect(receipts[0].documentKind.isBundleable)
        #expect(receipts[1].documentKind == .invoice)
        #expect(!receipts[1].documentKind.isBundleable)
    }

    @Test
    func unknownDocumentKindMapsToUnknown() throws {
        let json = """
        { "id": "r3", "approvalId": null, "vendor": "Other",
          "amount": null, "currency": "USD",
          "date": "2026-02-10", "documentKind": "supercrypto",
          "sourceAccount": "x", "submissionStatus": "pending" }
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(Receipt.self, from: json)
        #expect(r.documentKind == .unknown)
        #expect(!r.documentKind.isBundleable)
    }

    @Test
    func receiptFromServerRowAcceptsSnakeAndCamel() {
        let snake = ServerReceiptRow(
            id: "r-s", receivedAt: "2026-02-10",
            vendor: "Anthropic", amount: 9.0, currency: "USD",
            document_kind: "receipt", documentKind: nil,
            approval_id: "ap-1", approvalId: nil,
            account_email: "a@b.c", accountEmail: nil,
            submission_status: "pending", submissionStatus: nil
        )
        let camel = ServerReceiptRow(
            id: "r-c", receivedAt: "2026-02-10",
            vendor: "Anthropic", amount: 9.0, currency: "USD",
            document_kind: nil, documentKind: "receipt",
            approval_id: nil, approvalId: "ap-1",
            account_email: nil, accountEmail: "a@b.c",
            submission_status: nil, submissionStatus: "pending"
        )
        let s = Receipt.fromServerRow(snake)
        let c = Receipt.fromServerRow(camel)
        #expect(s.documentKind == .receipt)
        #expect(c.documentKind == .receipt)
        #expect(s.approvalId == "ap-1")
        #expect(c.approvalId == "ap-1")
        #expect(s.sourceAccount == "a@b.c")
        #expect(c.sourceAccount == "a@b.c")
    }

    // MARK: - ApprovalStatus forward-compat

    @Test
    func unknownApprovalStatusMapsToUnknown() throws {
        let json = "\"future-server-state\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(ApprovalStatus.self, from: json)
        #expect(status == .unknown)
    }

    @Test
    func knownApprovalStatusesDecode() throws {
        let cases: [(String, ApprovalStatus)] = [
            ("approved", .approved),
            ("denied", .denied),
            ("pending", .pending),
            ("requested", .requested),
            ("submitted", .submitted),
            ("reimbursed", .reimbursed),
            ("rejected", .rejected),
            ("awaiting_receipts", .awaitingReceipts),
            ("ready_for_submit", .readyForSubmit)
        ]
        for (raw, expected) in cases {
            let data = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ApprovalStatus.self, from: data)
            #expect(decoded == expected, "expected \(raw) → \(expected)")
        }
    }
}
