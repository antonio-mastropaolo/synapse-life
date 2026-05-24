import Foundation

/// Shared `JSONDecoder` factories for the Synapse client. Hosted in
/// `Models` so every consumer module (Networking, Features, tests) can
/// reach the same configuration without importing a heavier dependency.
extension JSONDecoder {
    /// Decoder used for finance payloads (`/api/finance/*`). `Transaction`
    /// owns its own per-field date handling because the route emits a
    /// `YYYY-MM-DD` day string, and the per-account legacy shape emits
    /// unix-seconds — neither matches an ISO-8601 timestamp. So the
    /// finance decoder is plain JSON with no global date strategy.
    public static let synapseFinance: JSONDecoder = {
        JSONDecoder()
    }()
}
