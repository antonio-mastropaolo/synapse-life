import Foundation
import Testing
import SwiftData
@testable import Persistence
@testable import Models

/// Smoke tests for the seam the shell uses to wire SwiftData into the
/// SwiftUI environment. The three configurations (`ephemeral`,
/// `namedFile`, `live`) all funnel through `PersistenceContainerFactory.make`;
/// these tests cover the first two — the App Group path needs a signed
/// host and is exercised by the cockpit smoke test, not here.
@Suite("PersistenceContainerFactory")
struct ContainerFactoryTests {

    @Test
    func ephemeralContainerIsUsable() throws {
        let container = try PersistenceContainerFactory.ephemeralContainer()
        // A fresh in-memory container should accept an insert and a fetch
        // without further wiring — the test is "does it spin up at all".
        let context = ModelContext(container)
        let row = PersistedFinanceAccount(
            id: "acc-1",
            institutionId: nil,
            institutionName: nil,
            name: "Smoke",
            officialName: nil,
            mask: nil,
            kindRaw: AccountKind.checking.rawValue,
            currency: "USD",
            currentBalance: Decimal(100),
            availableBalance: nil,
            limitAmount: nil,
            balanceCapturedAt: nil
        )
        context.insert(row)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<PersistedFinanceAccount>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Smoke")
    }

    @Test
    func schemaContainsAllModelTypes() {
        let entityNames = Set(PersistenceContainerFactory.schema.entities.map(\.name))
        #expect(entityNames.contains("PersistedFinanceAccount"))
        #expect(entityNames.contains("PersistedTransaction"))
        #expect(entityNames.contains("PersistedInvestmentPosition"))
        #expect(entityNames.contains("PersistedAuditLog"))
        #expect(entityNames.contains("PersistedNotification"))
        #expect(entityNames.count == 5)
    }

    @Test
    func namedFileRoundTripsAcrossContainerOpens() throws {
        // Use a unique temp URL so parallel runs do not collide.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("synnapse-pers-\(UUID().uuidString).store")
        defer {
            // Cleanup: SwiftData also writes -wal/-shm sidecars; remove
            // best-effort so a leftover from a previous failure doesn't
            // pollute the next run.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: tmp.appendingPathExtension(suffix.isEmpty ? "" : String(suffix.dropFirst())))
            }
            try? FileManager.default.removeItem(at: tmp)
        }

        // First open: create the file, insert a row, save, then drop the
        // container so the journal flushes.
        do {
            let container = try PersistenceContainerFactory.make(.namedFile(tmp))
            let context = ModelContext(container)
            context.insert(PersistedFinanceAccount(
                id: "acc-named",
                institutionId: "inst-1",
                institutionName: "First Republic",
                name: "Primary",
                officialName: nil,
                mask: "0001",
                kindRaw: AccountKind.checking.rawValue,
                currency: "USD",
                currentBalance: Decimal(string: "1234.56"),
                availableBalance: nil,
                limitAmount: nil,
                balanceCapturedAt: nil
            ))
            try context.save()
        }

        #expect(FileManager.default.fileExists(atPath: tmp.path))

        // Second open against the same URL — the previously-inserted row
        // should be visible.
        let container2 = try PersistenceContainerFactory.make(.namedFile(tmp))
        let context2 = ModelContext(container2)
        let rows = try context2.fetch(FetchDescriptor<PersistedFinanceAccount>())
        #expect(rows.count == 1)
        #expect(rows.first?.id == "acc-named")
        #expect(rows.first?.currentBalance == Decimal(string: "1234.56"))
    }
}
