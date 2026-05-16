import Foundation

/// One reimbursement approval letter — the "1" side of the 1-approval-to-N-receipts
/// rollup. Field shape mirrors the Synapse v2 route handler at
/// `app/api/approvals/route.ts`. The server's row shape is preserved verbatim in
/// `ServerApprovalRow` so wire-level decoding stays one-to-one; the public
/// `Approval` struct projects that into a native shape that's easier to render.
public struct Approval: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let vendor: String?
    public let approver: String
    public let approverRole: String
    public let category: String
    public let requestedAt: Date
    public let validUntil: Date?
    public let status: ApprovalStatus
    public let workdayURL: URL?
    public let totalAmount: Decimal?
    public let currency: String?

    public init(
        id: String,
        title: String,
        vendor: String?,
        approver: String,
        approverRole: String,
        category: String,
        requestedAt: Date,
        validUntil: Date?,
        status: ApprovalStatus,
        workdayURL: URL?,
        totalAmount: Decimal?,
        currency: String?
    ) {
        self.id = id
        self.title = title
        self.vendor = vendor
        self.approver = approver
        self.approverRole = approverRole
        self.category = category
        self.requestedAt = requestedAt
        self.validUntil = validUntil
        self.status = status
        self.workdayURL = workdayURL
        self.totalAmount = totalAmount
        self.currency = currency
    }
}

/// Forward-compatible enum: any unrecognized server string maps to `.unknown`
/// instead of throwing. The Synapse v2 route currently emits
/// `approved | denied | pending | requested`; the native taxonomy below also
/// covers the lifecycle states the receipts pipeline writes back, so this enum
/// is the union of both. New server-side values land as `.unknown` until the
/// native side adds a case.
public enum ApprovalStatus: String, Codable, Sendable, Hashable, CaseIterable {
    case awaitingReceipts = "awaiting_receipts"
    case readyForSubmit = "ready_for_submit"
    case submitted
    case reimbursed
    case rejected
    case approved
    case denied
    case pending
    case requested
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ApprovalStatus(rawValue: raw) ?? .unknown
    }
}

/// One receipt PDF row from `app/api/receipts/route.ts`. The native client
/// only needs the subset that drives the approvals tree + inspector — vendor,
/// amount, date, document kind, parent approval, source account.
public struct Receipt: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let approvalId: String?
    public let vendor: String
    public let amount: Decimal?
    public let currency: String
    public let date: String
    public let documentKind: DocumentKind
    public let sourceAccount: String
    public let submissionStatus: String

    public init(
        id: String,
        approvalId: String?,
        vendor: String,
        amount: Decimal?,
        currency: String,
        date: String,
        documentKind: DocumentKind,
        sourceAccount: String,
        submissionStatus: String
    ) {
        self.id = id
        self.approvalId = approvalId
        self.vendor = vendor
        self.amount = amount
        self.currency = currency
        self.date = date
        self.documentKind = documentKind
        self.sourceAccount = sourceAccount
        self.submissionStatus = submissionStatus
    }
}

/// Mirrors `lib/db/schema.ts#receiptDocumentKindEnum`. Only `.receipt` rows are
/// bundleable for Workday — see memory `project_document_kind`. The
/// `isBundleable` property locks that policy into the type system so callers
/// can't accidentally include invoices or refunds.
public enum DocumentKind: String, Codable, Sendable, Hashable, CaseIterable {
    case receipt
    case invoice
    case refund
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DocumentKind(rawValue: raw) ?? .unknown
    }

    public var isBundleable: Bool { self == .receipt }
}

/// Wraps both halves of the approvals view. The server today exposes
/// `/api/approvals` (approvals) and `/api/receipts` (receipts) as separate
/// routes; the repository composes them. When the server later adds a single
/// `/api/approvals/bundle` endpoint, the on-wire shape is already aligned.
public struct ApprovalsBundle: Codable, Sendable, Equatable {
    public let approvals: [Approval]
    public let receipts: [Receipt]

    public init(approvals: [Approval], receipts: [Receipt]) {
        self.approvals = approvals
        self.receipts = receipts
    }
}

// MARK: - Server wire shape

/// Wire-level row from `GET /api/approvals` (route.ts → `ApprovalRow`).
/// Keep field names matching the route JSON keys so decoding is mechanical;
/// `Approval.fromServerRow(_:)` does the projection into the native shape.
public struct ServerApprovalRow: Decodable, Sendable {
    public let id: String
    public let received_at: Double
    public let approver_name: String
    public let approver_role: String
    public let category: String
    public let approval_type: String
    public let amount_mentioned: Double?
    public let notes: String?
    public let linked_receipt_id: String?
    public let subject: String?
    public let sender_address: String?
}

public struct ServerApprovalsListResponse: Decodable, Sendable {
    public let approvals: [ServerApprovalRow]
}

extension Approval {
    /// Project a server row into the native `Approval`. The server emits
    /// `received_at` as a Unix timestamp (seconds). Approvals are valid for one
    /// year — derived field, matches the tree route's own derivation. There is
    /// no Workday URL in the v2 server today; we leave it nil and let the
    /// inspector show a "Submit/Save/Cancel must happen in Workday" note.
    public static func fromServerRow(_ row: ServerApprovalRow) -> Approval {
        let requested = Date(timeIntervalSince1970: row.received_at)
        let oneYear: TimeInterval = 365 * 24 * 60 * 60
        let valid = requested.addingTimeInterval(oneYear)
        let status = ApprovalStatus(rawValue: row.approval_type) ?? .unknown
        let title = row.subject ?? "\(row.approver_name) — \(row.category)"
        let amount: Decimal? = row.amount_mentioned.map { Decimal($0) }
        return Approval(
            id: row.id,
            title: title,
            vendor: nil,
            approver: row.approver_name,
            approverRole: row.approver_role,
            category: row.category,
            requestedAt: requested,
            validUntil: valid,
            status: status,
            workdayURL: nil,
            totalAmount: amount,
            currency: amount != nil ? "USD" : nil
        )
    }
}

/// Wire-level receipt from `GET /api/receipts`.
public struct ServerReceiptRow: Decodable, Sendable {
    public let id: String
    public let receivedAt: String
    public let vendor: String
    public let amount: Double?
    public let currency: String?
    public let document_kind: String?
    public let documentKind: String?
    public let approval_id: String?
    public let approvalId: String?
    public let account_email: String?
    public let accountEmail: String?
    public let submission_status: String?
    public let submissionStatus: String?

    enum CodingKeys: String, CodingKey {
        case id, receivedAt, vendor, amount, currency
        case document_kind, documentKind
        case approval_id, approvalId
        case account_email, accountEmail
        case submission_status, submissionStatus
    }
}

public struct ServerReceiptsListResponse: Decodable, Sendable {
    public let receipts: [ServerReceiptRow]
}

extension Receipt {
    public static func fromServerRow(_ row: ServerReceiptRow) -> Receipt {
        let kindRaw = row.documentKind ?? row.document_kind ?? "unknown"
        let kind = DocumentKind(rawValue: kindRaw) ?? .unknown
        let approval = row.approvalId ?? row.approval_id
        let account = row.accountEmail ?? row.account_email ?? ""
        let status = row.submissionStatus ?? row.submission_status ?? "pending"
        return Receipt(
            id: row.id,
            approvalId: approval,
            vendor: row.vendor,
            amount: row.amount.map { Decimal($0) },
            currency: row.currency ?? "USD",
            date: row.receivedAt,
            documentKind: kind,
            sourceAccount: account,
            submissionStatus: status
        )
    }
}
