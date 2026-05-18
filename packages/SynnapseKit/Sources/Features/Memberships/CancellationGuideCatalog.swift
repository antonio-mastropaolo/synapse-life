import Foundation

/// Static catalog of cancellation walkthroughs keyed by
/// `MerchantLogoResolver.domain` strings. Ships ~30 of the most-common
/// US personal-finance subscriptions so the detail surface has
/// something to render the moment the detector identifies a merchant.
///
/// LLM-generated guides will land in a follow-up commit; for v1 every
/// entry is `GuideSource.hardcoded` and reviewed by hand. Each guide
/// carries 3-6 imperative steps, an honest `averageTimeMinutes`
/// estimate (the "how long is this gonna take me" the friction tile
/// renders), and a `frictionLevel` so the UI can colour-code the chip.
///
/// The catalog is also the home for:
///   * `alternatives(for:)` — cheaper / equivalent services the
///     ALTERNATIVES tile renders.
///   * `annualPrice(for:)` — single-source-of-truth for "annual vs
///     monthly" math; the optimiser uses it to emit `switchToAnnual`
///     tips only when the annual figure beats 12× the monthly.
///   * `cheaperTier(for:)` — text + price for the DOWNGRADE tile.
public enum CancellationGuideCatalog {

    // MARK: - Public API

    /// Hardcoded cancellation guide for a merchant domain, or `nil`
    /// if we don't ship one yet.
    public static func guide(for domain: String) -> CancellationGuide? {
        guides[domain.lowercased()]
    }

    /// Suggested alternatives for a merchant domain — feeds the
    /// ALTERNATIVES tile on the detail surface.
    public static func alternatives(for domain: String) -> [String] {
        alternativesTable[domain.lowercased()] ?? []
    }

    /// Best-known annual price for a merchant domain. The optimiser
    /// only emits a `switchToAnnual` tip when this exists AND
    /// `annual/12 < monthly`.
    public static func annualPrice(for domain: String) -> Decimal? {
        annualPriceTable[domain.lowercased()]
    }

    /// Cheaper-tier descriptor used by the DOWNGRADE tile + the
    /// `downgrade` optimisation tip. `label` reads as plain English
    /// ("Ad-supported tier"), `monthlyPrice` is what the tier costs.
    public static func cheaperTier(for domain: String) -> (label: String, monthlyPrice: Decimal)? {
        cheaperTierTable[domain.lowercased()]
    }

    /// All domains we ship a guide for. Used by tests + the
    /// "did we forget to map this merchant" telemetry the optimiser
    /// surfaces in debug builds.
    public static var supportedDomains: [String] {
        Array(guides.keys).sorted()
    }

    // MARK: - Guides

    private static let guides: [String: CancellationGuide] = [
        "netflix.com": CancellationGuide(
            steps: [
                "Sign in at netflix.com/account",
                "Open Membership & Billing",
                "Click Cancel Membership",
                "Confirm cancellation on the next screen"
            ],
            averageTimeMinutes: 3,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://www.netflix.com/CancelPlan"),
            source: .hardcoded
        ),
        "spotify.com": CancellationGuide(
            steps: [
                "Sign in at spotify.com/account",
                "Open Manage your plan",
                "Pick Change plan, then Cancel Premium",
                "Confirm — Spotify keeps you Premium until the next billing date"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://www.spotify.com/account/subscription/"),
            source: .hardcoded
        ),
        "hulu.com": CancellationGuide(
            steps: [
                "Sign in at hulu.com/account",
                "Scroll to Your Subscription",
                "Click Cancel",
                "Decline retention offers and confirm cancellation"
            ],
            averageTimeMinutes: 5,
            frictionLevel: .moderate,
            cancelUrl: URL(string: "https://secure.hulu.com/account/cancel"),
            source: .hardcoded
        ),
        "disneyplus.com": CancellationGuide(
            steps: [
                "Sign in at disneyplus.com/account",
                "Open Subscription",
                "Tap Cancel Subscription",
                "Confirm — Disney+ retains access through the paid period"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://www.disneyplus.com/account/subscription"),
            source: .hardcoded
        ),
        "hbomax.com": CancellationGuide(
            steps: [
                "Sign in at max.com",
                "Click your profile, then Subscription",
                "Choose Manage Subscription, then Cancel",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 5,
            frictionLevel: .moderate,
            cancelUrl: URL(string: "https://auth.max.com/subscription"),
            source: .hardcoded
        ),
        "nytimes.com": CancellationGuide(
            steps: [
                "Sign in at nytimes.com",
                "Open your account, then Manage Subscription",
                "Click Cancel Subscription",
                "Decline retention offers (the Times will push 50% off)",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 8,
            frictionLevel: .hard,
            cancelUrl: URL(string: "https://www.nytimes.com/subscription/manage"),
            source: .hardcoded
        ),
        "apple.com": CancellationGuide(
            steps: [
                "Open System Settings on Mac (or Settings on iPhone)",
                "Tap your Apple ID, then Subscriptions",
                "Pick iCloud+ (or the Apple service to cancel)",
                "Choose Cancel Subscription and confirm"
            ],
            averageTimeMinutes: 3,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://apps.apple.com/account/subscriptions"),
            source: .hardcoded
        ),
        "adobe.com": CancellationGuide(
            steps: [
                "Sign in at account.adobe.com/plans",
                "Click Manage Plan on the active subscription",
                "Choose Cancel your plan",
                "Pick a reason, decline retention offers",
                "Review the early termination fee if within first 14 days, then confirm"
            ],
            averageTimeMinutes: 12,
            frictionLevel: .hard,
            cancelUrl: URL(string: "https://account.adobe.com/plans"),
            source: .hardcoded
        ),
        "dropbox.com": CancellationGuide(
            steps: [
                "Sign in at dropbox.com/account/plan",
                "Click Cancel plan",
                "Pick a reason and confirm",
                "Dropbox downgrades to Basic at the end of the billing period"
            ],
            averageTimeMinutes: 5,
            frictionLevel: .moderate,
            cancelUrl: URL(string: "https://www.dropbox.com/account/plan"),
            source: .hardcoded
        ),
        "github.com": CancellationGuide(
            steps: [
                "Sign in at github.com/settings/billing",
                "Open Plans and usage",
                "Click Downgrade to Free",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://github.com/settings/billing/plans"),
            source: .hardcoded
        ),
        "openai.com": CancellationGuide(
            steps: [
                "Sign in at chat.openai.com",
                "Click your profile, then My Plan",
                "Choose Manage my subscription",
                "Click Cancel Plan and confirm"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://chat.openai.com/#settings/Subscription"),
            source: .hardcoded
        ),
        "anthropic.com": CancellationGuide(
            steps: [
                "Sign in at claude.ai",
                "Open Settings, then Billing",
                "Click Manage subscription",
                "Choose Cancel plan and confirm"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://claude.ai/settings/billing"),
            source: .hardcoded
        ),
        "amazon.com": CancellationGuide(
            steps: [
                "Sign in at amazon.com/prime",
                "Hover over Account & Lists, choose Prime Membership",
                "Click Manage Membership, then End Membership",
                "Walk through three retention screens (Amazon makes this hard)",
                "Confirm — Prime stays active through the paid period"
            ],
            averageTimeMinutes: 10,
            frictionLevel: .hard,
            cancelUrl: URL(string: "https://www.amazon.com/gp/primecentral"),
            source: .hardcoded
        ),
        "doordash.com": CancellationGuide(
            steps: [
                "Open the DoorDash app or doordash.com",
                "Tap Account, then Manage DashPass",
                "Pick End Subscription",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://www.doordash.com/accounts/dashpass"),
            source: .hardcoded
        ),
        "uber.com": CancellationGuide(
            steps: [
                "Open the Uber app",
                "Tap Account, then Uber One",
                "Choose Manage membership, then End membership",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://m.uber.com/go/uber-one"),
            source: .hardcoded
        ),
        "youtube.com": CancellationGuide(
            steps: [
                "Sign in at youtube.com",
                "Click your avatar, then Purchases and memberships",
                "Pick YouTube Premium",
                "Click Deactivate and confirm cancellation"
            ],
            averageTimeMinutes: 5,
            frictionLevel: .moderate,
            cancelUrl: URL(string: "https://www.youtube.com/paid_memberships"),
            source: .hardcoded
        ),
        "nike.com": CancellationGuide(
            steps: [
                "Open the Nike Training Club / Run Club app",
                "Tap Profile, then Settings, then Membership",
                "Choose Cancel Subscription",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 5,
            frictionLevel: .moderate,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "equinox.com": CancellationGuide(
            steps: [
                "Equinox requires written cancellation",
                "Email your home club's General Manager from your member-of-record address",
                "State your full name, member ID, and effective cancel date (45-day notice required)",
                "Follow up by phone if you don't get a confirmation within 5 business days",
                "Save the confirmation email — billing has been known to continue"
            ],
            averageTimeMinutes: 25,
            frictionLevel: .hard,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "goldsgym.com": CancellationGuide(
            steps: [
                "Print and complete the Gold's Gym cancellation form",
                "Bring it to your home club in person (most locations require this)",
                "Pay the 30-day notice charge if applicable",
                "Keep the signed receipt — you may need it for chargebacks"
            ],
            averageTimeMinutes: 30,
            frictionLevel: .hard,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "verizon.com": CancellationGuide(
            steps: [
                "Call Verizon at 1-844-837-2262 (you cannot cancel online)",
                "Walk through ID verification",
                "State you want to cancel — expect 2 retention offers",
                "Confirm cancellation and ask for an email confirmation",
                "Save the cancellation reference number"
            ],
            averageTimeMinutes: 25,
            frictionLevel: .hard,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "att.com": CancellationGuide(
            steps: [
                "Call AT&T at 1-800-288-2020",
                "Say 'cancel service' at the prompt",
                "Walk through ID verification",
                "Decline retention offers, confirm cancellation",
                "Request a written confirmation email"
            ],
            averageTimeMinutes: 25,
            frictionLevel: .hard,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "tmobile.com": CancellationGuide(
            steps: [
                "Call T-Mobile at 611 from a T-Mobile phone (or 1-800-937-8997)",
                "Verify your account PIN",
                "Request cancellation, decline retention offers",
                "Confirm the final bill amount and any device payoff",
                "Ask for an email confirmation"
            ],
            averageTimeMinutes: 22,
            frictionLevel: .hard,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "traderjoes.com": CancellationGuide(
            steps: [
                "Trader Joe's has no paid membership — this charge is likely a grocery purchase, not a subscription",
                "Review the underlying transaction in your bank app",
                "If a recurring charge actually exists, contact your bank to investigate"
            ],
            averageTimeMinutes: 2,
            frictionLevel: .easy,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "wholefoodsmarket.com": CancellationGuide(
            steps: [
                "Whole Foods doesn't sell a paid membership; recurring charges likely come from Amazon Prime perks",
                "Cancel Amazon Prime via amazon.com/prime to stop the related Whole Foods discount",
                "Or contact your bank if the charge looks unauthorized"
            ],
            averageTimeMinutes: 3,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://www.amazon.com/gp/primecentral"),
            source: .hardcoded
        ),
        "starbucks.com": CancellationGuide(
            steps: [
                "Starbucks Rewards is free — no subscription to cancel",
                "If you're seeing recurring auto-reload charges, open the Starbucks app",
                "Tap your card, then Manage, then Off for Auto Reload"
            ],
            averageTimeMinutes: 3,
            frictionLevel: .easy,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "chipotle.com": CancellationGuide(
            steps: [
                "Chipotle Rewards is free — no subscription to cancel",
                "If you see a recurring charge, it's likely the Chipotlane Pickup auto-pay; cancel any open order in the app",
                "Otherwise contact your bank to investigate"
            ],
            averageTimeMinutes: 3,
            frictionLevel: .easy,
            cancelUrl: nil,
            source: .hardcoded
        ),
        "etsy.com": CancellationGuide(
            steps: [
                "Sign in at etsy.com",
                "Open Account, then Settings, then Subscriptions (sellers only)",
                "Pick the Etsy Plus or Pattern plan",
                "Click Cancel subscription and confirm"
            ],
            averageTimeMinutes: 6,
            frictionLevel: .moderate,
            cancelUrl: URL(string: "https://www.etsy.com/your/account/subscriptions"),
            source: .hardcoded
        ),
        "ebay.com": CancellationGuide(
            steps: [
                "Sign in at ebay.com",
                "Open My eBay, then Account, then Subscriptions",
                "Click Unsubscribe next to the active plan",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 5,
            frictionLevel: .moderate,
            cancelUrl: URL(string: "https://www.ebay.com/myb/Subscriptions"),
            source: .hardcoded
        ),
        "paypal.com": CancellationGuide(
            steps: [
                "Sign in at paypal.com",
                "Open Settings, then Payments, then Manage automatic payments",
                "Select the merchant to cancel",
                "Click Cancel and confirm"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: URL(string: "https://www.paypal.com/myaccount/autopay/"),
            source: .hardcoded
        ),
        "venmo.com": CancellationGuide(
            steps: [
                "Open the Venmo app",
                "Tap Me, then Settings, then Subscriptions (if any)",
                "Choose the active subscription and tap Cancel",
                "Confirm cancellation"
            ],
            averageTimeMinutes: 4,
            frictionLevel: .easy,
            cancelUrl: nil,
            source: .hardcoded
        )
    ]

    // MARK: - Alternatives

    private static let alternativesTable: [String: [String]] = [
        "netflix.com":     ["Hulu Basic — $7.99/mo", "Netflix ad-supported — $7.99/mo", "Library Kanopy — free with library card"],
        "spotify.com":     ["Apple Music — $10.99/mo", "YouTube Music — $10.99/mo", "Tidal HiFi — $10.99/mo"],
        "hulu.com":        ["Netflix ad-tier — $7.99/mo", "Disney+ basic — $9.99/mo", "Peacock Premium — $7.99/mo"],
        "disneyplus.com":  ["Disney+ ad-supported — $9.99/mo", "Hulu basic — $7.99/mo"],
        "hbomax.com":      ["Netflix standard — $15.49/mo", "Hulu ad-free — $17.99/mo", "Library Kanopy — free"],
        "nytimes.com":     ["WSJ digital — $19.99/mo", "Washington Post — $4/mo first year", "Apple News+ — $12.99/mo"],
        "apple.com":       ["Google One 200 GB — $2.99/mo", "Dropbox Plus 2 TB — $11.99/mo", "Local Time Machine — free"],
        "adobe.com":       ["Affinity bundle — $164.99 one-time", "Figma free tier", "Pixelmator Pro — $49.99 one-time"],
        "dropbox.com":     ["iCloud+ 2 TB — $9.99/mo", "Google One 2 TB — $9.99/mo", "Sync.com 2 TB — $8/mo"],
        "github.com":      ["GitHub Free for personal repos", "GitLab Free for unlimited private repos"],
        "openai.com":      ["Claude Pro — $20/mo", "Gemini Advanced — $19.99/mo", "Free tier of ChatGPT"],
        "anthropic.com":   ["ChatGPT Plus — $20/mo", "Gemini Advanced — $19.99/mo", "Claude free tier"],
        "amazon.com":      ["Walmart+ — $12.95/mo", "Target Circle 360 — $99/year", "Costco Gold Star — $65/year"],
        "doordash.com":    ["Uber One — $9.99/mo", "Grubhub+ — $9.99/mo", "Order direct from restaurants"],
        "uber.com":        ["DashPass — $9.99/mo", "Lyft Pink — $9.99/mo"],
        "youtube.com":     ["Spotify Premium — $10.99/mo (no video ads via app blocker)", "YouTube Family — $22.99/mo for 5", "Free tier with ads"],
        "equinox.com":     ["Planet Fitness Black Card — $24.99/mo", "Crunch Fitness — $29.99/mo", "Local YMCA — ~$50/mo"],
        "goldsgym.com":    ["Planet Fitness — $10/mo", "Crunch Fitness — $9.99/mo", "Bodyweight + free apps"],
        "verizon.com":     ["Mint Mobile 5GB — $15/mo", "Visible by Verizon — $25/mo unlimited", "US Mobile — $20/mo"],
        "att.com":         ["Cricket Wireless — $30/mo", "Mint Mobile — $15/mo", "US Mobile — $20/mo"],
        "tmobile.com":     ["Mint Mobile (T-Mobile network) — $15/mo", "US Mobile — $20/mo"]
    ]

    // MARK: - Annual pricing

    /// Annual prices (USD) for merchants that offer a yearly tier. Use
    /// the official advertised price; the optimiser does the
    /// `annual / 12 < monthly` comparison.
    private static let annualPriceTable: [String: Decimal] = [
        "netflix.com":     0,              // Netflix has no annual tier
        "spotify.com":     0,              // Spotify Individual is monthly-only in the US
        "hulu.com":        79.99,          // Hulu (with ads) annual
        "disneyplus.com":  109.99,         // Disney+ Premium annual
        "hbomax.com":      99.99,          // Max with ads annual
        "nytimes.com":     50,             // First-year promo, monthly thereafter
        "apple.com":       0,              // iCloud+ is monthly-only
        "adobe.com":       599.88,         // Creative Cloud All Apps annual prepaid
        "dropbox.com":     119.88,         // Dropbox Plus annual
        "github.com":      0,
        "openai.com":      0,              // ChatGPT Plus is monthly-only
        "anthropic.com":   0,              // Claude Pro is monthly-only
        "amazon.com":      139,            // Prime annual
        "doordash.com":    96,             // DashPass annual
        "uber.com":        99.99,          // Uber One annual
        "youtube.com":     139.99          // YouTube Premium annual
    ]

    // Skip table entries where the annual figure is `0` — used as a
    // sentinel for "no annual tier" so the optimiser bails cleanly.
    static func hasAnnualPlan(for domain: String) -> Bool {
        guard let price = annualPriceTable[domain.lowercased()] else { return false }
        return price > 0
    }

    // MARK: - Downgrade tiers

    private static let cheaperTierTable: [String: (label: String, monthlyPrice: Decimal)] = [
        "netflix.com":   ("Ad-supported tier",      7.99),
        "spotify.com":   ("Student plan",           5.99),
        "hulu.com":      ("Hulu with ads",          7.99),
        "disneyplus.com":("Disney+ Basic with ads", 9.99),
        "hbomax.com":    ("Max with ads",           9.99),
        "nytimes.com":   ("Games-only digital",     1.25),
        "apple.com":     ("iCloud+ 50 GB",          0.99),
        "adobe.com":     ("Photography plan",       9.99),
        "dropbox.com":   ("Dropbox Basic",          0),
        "openai.com":    ("ChatGPT Free",           0),
        "anthropic.com": ("Claude Free",            0),
        "youtube.com":   ("YouTube Premium Lite",   7.99),
        "doordash.com":  ("DashPass Student",       4.99),
        "amazon.com":    ("Prime Student",          7.49)
    ]
}
