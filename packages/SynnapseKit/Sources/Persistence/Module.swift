import Foundation

/// SynnapseKit persistence module.
///
/// Provides a SwiftData-backed local store for the Sendable DTOs in the
/// `Models` module:
///
/// - `PersistedFinanceAccount`     ↔  `FinanceAccount`
/// - `PersistedTransaction`        ↔  `Transaction`
/// - `PersistedInvestmentPosition` ↔  `InvestmentPosition`
/// - `PersistedAuditLog`           — append-only event store (no DTO mirror;
///                                    consumed by the in-app history view)
///
/// View models talk to `TransactionStore` / `AccountStore` /
/// `InvestmentStore` (all `ModelActor`s) which expose Sendable-DTO APIs so
/// `@Model` instances never cross the actor boundary. The
/// `ContainerFactory` is the single seam where the shell wires the
/// `ModelContainer` into the SwiftUI environment.
///
/// Money values are persisted as `Decimal` to preserve exactness end-to-end.
/// All DTO ↔ persisted conversions live in `Projections.swift`.
///
/// Empty-container seeding is opt-in via the `seedIfEmpty(...)` helper on
/// `TransactionStore`; the cockpit's existing `AppLifecycle/DemoData.swift`
/// remains the canonical source of seed fixtures and is invoked only when
/// the store is empty AND when the shell wires the demo-data path.
public enum PersistenceModule {
    public static let schemaVersion: String = "1.0.0"
}
