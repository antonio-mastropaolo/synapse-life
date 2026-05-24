import Foundation
import Observation
import Models

/// View model that owns the detected `[DetectedSubscription]` state.
/// Refresh is synchronous (the detector is pure-logic, deterministic,
/// and cheap) so the macOS and iOS surfaces can call it directly off
/// the `AppModel.bootstrapIfNeeded()` path.
///
/// The `monthlyTotal` / `yearlyTotal` projections are derived from the
/// list — the view binds to them directly so the header re-renders
/// when `refresh(...)` lands a new detection set.
@MainActor
@Observable
public final class SubscriptionsViewModel {

    public private(set) var subscriptions: [DetectedSubscription] = []
    public private(set) var lastRefreshed: Date?

    public init() {}

    /// Inject a pre-detected list (snapshot tests / previews).
    public init(subscriptions: [DetectedSubscription]) {
        self.subscriptions = subscriptions
        self.lastRefreshed = Date()
    }

    public func refresh(transactions: [Transaction], today: Date = Date()) {
        self.subscriptions = SubscriptionDetector.detectSubscriptions(
            transactions: transactions, today: today
        )
        self.lastRefreshed = today
    }

    public var monthlyTotal: Decimal {
        SubscriptionDetector.monthlyTotal(subscriptions)
    }

    public var yearlyTotal: Decimal {
        SubscriptionDetector.yearlyTotal(subscriptions)
    }

    public var count: Int { subscriptions.count }
}

/// Maps a merchant string to an SF Symbol so subscription cards
/// paint without raster artwork. The list is intentionally curated —
/// every brand a user is likely to see here gets a deliberate glyph;
/// the long-tail fallback is `rectangle.stack`.
public enum MerchantIconResolver {

    /// Returns an SF Symbol name for the merchant. Lookup is
    /// case-insensitive and matches on substring so "NETFLIX.COM" and
    /// "Netflix Premium" both resolve to the same icon.
    public static func symbol(for merchant: String) -> String {
        let upper = merchant.uppercased()
        for (tokens, symbol) in mapping {
            if tokens.contains(where: { upper.contains($0) }) {
                return symbol
            }
        }
        return "rectangle.stack"
    }

    private static let mapping: [(tokens: [String], symbol: String)] = [
        (["NETFLIX"],                   "play.rectangle.fill"),
        (["SPOTIFY"],                   "music.note"),
        (["APPLE", "ICLOUD"],           "applelogo"),
        (["NYTIMES", "WSJ"],            "newspaper.fill"),
        (["ANTHROPIC", "CLAUDE"],       "brain"),
        (["OPENAI", "CHATGPT"],         "brain.head.profile"),
        (["HBO", "MAX"],                "tv.fill"),
        (["HULU"],                      "play.tv.fill"),
        (["DISNEY"],                    "sparkles.tv.fill"),
        (["GITHUB"],                    "chevron.left.forwardslash.chevron.right"),
        (["DROPBOX"],                   "shippingbox.fill"),
        (["ADOBE"],                     "paintbrush.fill"),
        (["SIRIUS"],                    "radio.fill"),
        (["GOLDS GYM", "GYM"],          "figure.run"),
    ]
}
