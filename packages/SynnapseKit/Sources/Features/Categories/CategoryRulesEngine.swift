import Foundation
import Models

/// Auto-categorizer. A pure function over a transaction's `name` /
/// `merchantName` string that returns a [[CategoryID]].
///
/// The shape is a single ordered `[(CategoryID, NSRegularExpression)]`
/// table. First match wins — priority lives in table order, NOT in a
/// scoring pass. Per [[feedback_pattern_match_not_classifier]]: no
/// `Classify*` types, no scoring fallbacks, no LLM in the hot path. The
/// caller wires the result through to the UI; the server-supplied
/// category string still rides along on the Transaction as before.
public enum CategoryRulesEngine {

    /// The canonical default rule set. Order matters — ambiguous strings
    /// resolve to whichever id appears first in this list. The intent:
    ///   • Subscriptions before Entertainment so "STEAM" → entertainment,
    ///     but "NETFLIX" → subscriptions (Netflix is recurring billing).
    ///   • Income before Transfers so "DIRECT DEP" wins over a generic
    ///     "TRANSFER" keyword.
    ///   • Fees last (before Other) so a literal "FEE" line isn't
    ///     stolen by a merchant whose name happens to contain it.
    public static let defaultRules: [(CategoryID, String)] = [
        // Income — payroll/ACH credits read first so they don't get
        // swallowed by the generic "TRANSFER" line in Transfers.
        (.income, #"(?i)\b(PAYROLL|ACH\s*CREDIT|DIRECT\s*DEP(?:OSIT)?|SALARY|DEPOSIT)\b"#),

        // Subscriptions — recurring SaaS / streaming / news. Anthropic /
        // OpenAI live here because they bill monthly (mirrors the
        // synapse-v2 receipt taxonomy where they're recurring SaaS).
        (.subscriptions, #"(?i)\b(NETFLIX|SPOTIFY|ANTHROPIC|OPENAI|APPLE\.COM/BILL|NYTIMES|HBO|HULU|DISNEY\s*PLUS|YOUTUBE\s*PREMIUM|ADOBE|FIGMA|NOTION|DROPBOX|ICLOUD|GITHUB|CHATGPT|CLAUDE)\b"#),

        // Restaurants — chains common enough to cover most lines.
        (.restaurants, #"(?i)\b(PANERA|CHIPOTLE|STARBUCKS|SHAKE\s*SHACK|MCDONALDS|MCDONALD'?S|BLUE\s*BOTTLE|CHICK[- ]?FIL[- ]?A|TACO\s*BELL|SUBWAY|DOMINOS|PIZZA\s*HUT|DUNKIN|WENDY'?S|BURGER\s*KING|KFC|POPEYES|SWEETGREEN|CAVA|DOORDASH|UBER\s*EATS|GRUBHUB|RESTAURANT|COFFEE)\b"#),

        // Groceries.
        (.groceries, #"(?i)\b(WHOLE\s*FOODS|TRADER\s*JOE|TRADER\s*JOE'?S|KROGER|WEGMANS|SAFEWAY|ALDI|PUBLIX|COSTCO|SAMS?\s*CLUB|H[- ]?E[- ]?B|HARRIS\s*TEETER|GIANT|STOP\s*&\s*SHOP|FOOD\s*LION|GROCERY)\b"#),

        // Loans / BNPL.
        (.loans, #"(?i)\b(AFFIRM|KLARNA|BREAD\s*FINANCIAL|AFTERPAY|SOFI|LOAN|MORTGAGE|STUDENT\s*LOAN|NAVIENT|GREAT\s*LAKES)\b"#),

        // Clothing.
        (.clothing, #"(?i)\b(NIKE|ADIDAS|ZARA|UNIQLO|H&M|H\s*AND\s*M|LULULEMON|GAP|OLD\s*NAVY|J\.?\s*CREW|MADEWELL|BANANA\s*REPUBLIC|PATAGONIA|NORTH\s*FACE|UNDER\s*ARMOUR|REI|ASOS)\b"#),

        // Personal care — gyms, barbers, salons.
        (.personalCare, #"(?i)\b(GOLD'?S\s*GYM|PLANET\s*FITNESS|EQUINOX|SUPERCUTS|GREAT\s*CLIPS|HAIR|BARBER|SALON|SPA|MASSAGE|YOGA|PILATES|CRUNCH\s*FITNESS)\b"#),

        // Entertainment — movies, games, music streaming hardware.
        (.entertainment, #"(?i)\b(AMC|REGAL|CINEMARK|SIRIUSXM|STEAM|XBOX|PLAYSTATION|NINTENDO|TICKETMASTER|STUBHUB|LIVE\s*NATION|MOVIE|CINEMA|CONCERT|ARCADE)\b"#),

        // Fees — flagged literal strings only. Kept near the end so a
        // merchant containing "fee" in its name doesn't get hijacked.
        (.fees, #"(?i)\b(OVERDRAFT|WIRE\s*FEE|ATM\s*FEE|FOREIGN\s*TRANSACTION\s*FEE|SERVICE\s*FEE|LATE\s*FEE|MAINTENANCE\s*FEE|NSF\s*FEE|FINANCE\s*CHARGE)\b"#),

        // Transfers — last because "TRANSFER" alone is a generic word.
        (.transfers, #"(?i)\b(ZELLE|VENMO|CASH\s*APP|PAYPAL\s*XFER|TRANSFER|XFER|WIRE\s*TRANSFER|INTERNAL\s*TRANSFER)\b"#),
    ]

    /// Compiled form of [[defaultRules]]. Computed once and cached. A bad
    /// pattern would be a programmer error; we fatalError so it surfaces
    /// in unit tests rather than silently mis-categorizing in prod.
    public static let compiled: [(CategoryID, NSRegularExpression)] = defaultRules.map { id, pattern in
        do {
            let r = try NSRegularExpression(pattern: pattern, options: [])
            return (id, r)
        } catch {
            fatalError("CategoryRulesEngine: invalid regex for \(id.slug): \(error)")
        }
    }

    /// First-match-wins lookup. `description` is typically the
    /// transaction's `name` field; the caller may prepend `merchantName`
    /// if it has one (we treat both as a single haystack).
    public static func categorize(_ description: String) -> CategoryID {
        let s = description as NSString
        let range = NSRange(location: 0, length: s.length)
        for (id, regex) in compiled {
            if regex.firstMatch(in: description, options: [], range: range) != nil {
                return id
            }
        }
        return .other
    }

    /// Convenience for callers holding a `Transaction`. We feed both the
    /// description and the merchant name into the engine because some
    /// banks shove the brand into one or the other inconsistently.
    public static func categorize(_ transaction: Transaction) -> CategoryID {
        var haystack = transaction.name
        if let m = transaction.merchantName, !m.isEmpty {
            haystack += " " + m
        }
        return categorize(haystack)
    }
}
