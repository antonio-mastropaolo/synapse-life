import Foundation
import Models

/// One row in the Dashboard inbox. Wraps a [[Transaction]] with the
/// review-state bit that the existing ledger model deliberately does
/// not carry — Copilot's Dashboard is an inbox of un-reviewed rows, not
/// a re-paint of the transactions ledger, so the review flag is owned
/// here rather than added to the shared `Transaction` schema.
///
/// We keep this as a value type with a stable identity (`id` mirrors
/// the transaction id) so the view model can drive selection through
/// `Set<String>` and the SwiftUI list can identify rows for diffing
/// without re-checking each transaction's hash.
public struct DashboardEntry: Sendable, Hashable, Identifiable {

    public let transaction: Transaction

    /// True when the user has marked this row as reviewed. The
    /// dashboard renders only `reviewed == false` rows.
    public var reviewed: Bool

    /// Optional row subtitle. Copilot shows a truncated description
    /// beneath the merchant name (e.g. "Purchase Klarna*klarn" under
    /// "Klarna"). When nil the view falls back to the account name,
    /// then to the transaction's `name` if it differs from the
    /// merchant. Carried separately so demo fixtures can be authored
    /// with the exact Copilot copy.
    public let description: String?

    public init(
        transaction: Transaction,
        reviewed: Bool = false,
        description: String? = nil
    ) {
        self.transaction = transaction
        self.reviewed = reviewed
        self.description = description
    }

    /// Identity flows through the underlying transaction so SwiftUI's
    /// list diffing aligns with the network's row ids. Two entries
    /// that differ only by `reviewed` carry the same id by design —
    /// the toggle is an in-place update, not a row replacement.
    public var id: String { transaction.id }
}
