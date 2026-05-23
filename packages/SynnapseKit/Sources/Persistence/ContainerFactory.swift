import Foundation
import SwiftData

/// Builds the `ModelContainer` the shell injects into the SwiftUI
/// environment. Three configurations:
///
/// - **`live`**: on-disk store in the App Group container so a future
///   widget / share-extension can read the same data. Falls back to the
///   app's default documents directory when the App Group can't be
///   resolved (unsigned `swift test`, dev simulator without the
///   entitlement).
/// - **`ephemeral`**: in-memory only. Used by `swift test`, SwiftUI
///   previews, and the "Reset on next launch" diagnostic.
/// - **`namedFile`**: on-disk at a caller-supplied URL. Used by migration
///   tests and by the demo-data smoke test that needs a file it can
///   delete between runs.
public enum PersistenceContainerFactory {

    public enum Configuration: Sendable {
        case live(appGroupIdentifier: String?)
        case ephemeral
        case namedFile(URL)
    }

    /// The complete schema this app version persists. Adding a new
    /// `@Model` type here is the only place a migration needs to start.
    public static let schema = Schema([
        PersistedFinanceAccount.self,
        PersistedTransaction.self,
        PersistedInvestmentPosition.self,
        PersistedAuditLog.self,
        PersistedNotification.self,
        PersistedRecurring.self
    ])

    /// Build a `ModelContainer` for the requested configuration. Throws
    /// `Error` from SwiftData if the underlying file store cannot be
    /// opened — callers should treat the failure as fatal and surface
    /// it to the user, not silently fall through to an empty container.
    public static func make(_ configuration: Configuration) throws -> ModelContainer {
        let config: ModelConfiguration
        switch configuration {
        case .ephemeral:
            config = ModelConfiguration(isStoredInMemoryOnly: true)
        case .namedFile(let url):
            config = ModelConfiguration(url: url)
        case .live(let appGroup):
            if let group = appGroup,
               let dir = FileManager.default.containerURL(
                   forSecurityApplicationGroupIdentifier: group
               ) {
                let url = dir.appendingPathComponent("Synnapse.store", isDirectory: false)
                config = ModelConfiguration(url: url)
            } else {
                // No App Group available (unsigned, missing entitlement) —
                // fall back to the documents directory so dev launches and
                // simulator runs still get a store. We log a one-shot
                // warning so the dev sees the fallback.
                let docs = try FileManager.default.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                let url = docs.appendingPathComponent("Synnapse.store", isDirectory: false)
                #if DEBUG
                if appGroup != nil {
                    print("[Persistence] App Group container not available; using docs fallback at \(url.path)")
                }
                #endif
                config = ModelConfiguration(url: url)
            }
        }
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Convenience for the most common test path.
    public static func ephemeralContainer() throws -> ModelContainer {
        try make(.ephemeral)
    }
}
