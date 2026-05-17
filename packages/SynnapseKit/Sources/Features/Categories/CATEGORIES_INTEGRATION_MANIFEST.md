# Categories — Integration Manifest

Owned by: agent 3 (Copilot redesign — categories surface + pill system)
Worktree: `worktree-copilot-categories`

## What this module ships

- `CategoryID` — canonical id for the pill system. 10 defaults + `.other` + `.custom(slug)`.
- `CategoryRulesEngine.categorize(_:)` — pure function, ordered `[id, regex]` table, first-match wins.
- `CategoryResolver.resolve(_:)` — bridges `Transaction.category` (server string) → `CategoryID`.
- `CategoryStore` — actor, UserDefaults-backed, holds user-added customs.
- `CategoryPill` — SwiftUI view, `.compact` and `.large` sizes, uppercase 9pt/11pt SF Mono bold white on category color.
- `CategoriesView` + `CategoriesViewModel` — the Categories surface (Copilot-style list + sparkline + new-category sheet).

## Canonical id → hex map

These are the colors the rest of the redesign team must read for parity:

| `CategoryID`        | Slug              | Hex       | Emoji   |
| ------------------- | ----------------- | --------- | ------- |
| `.restaurants`      | `restaurants`     | `#4CAF6B` | 🍽️      |
| `.subscriptions`    | `subscriptions`   | `#A06CD5` | 🔁      |
| `.groceries`        | `groceries`       | `#7CB342` | 🛒      |
| `.loans`            | `loans`           | `#E53935` | 💳      |
| `.clothing`         | `clothing`        | `#EC407A` | 👕      |
| `.income`           | `income`          | `#26A69A` | 💰      |
| `.transfers`        | `transfers`       | `#42A5F5` | 🔀      |
| `.personalCare`     | `personal-care`   | `#FFB74D` | 💈      |
| `.entertainment`    | `entertainment`   | `#FFA726` | 🎬      |
| `.fees`             | `fees`            | `#8D6E63` | ⚠️      |
| `.other`            | `other`           | `#78909C` | •       |

Custom categories carry their own hex on `CustomCategoryRecord.hex`.

## Departure from the brief — `TokenSet.category(_:)`

The brief asked us to emit a `category(_:)` token method on `TokenSet` so
agent 1's design-system pass picks the palette up. We did **not** add that
extension here because:

1. DesignSystem is owned by agent 1, and the parallelization rules say
   we must not touch it.
2. Emitting a `TokenSet.category(_:)` extension from the Features module
   would put it on the wrong side of the dependency graph (Features
   depends on DesignSystem, not vice versa) and would not be visible to
   any DesignSystem-only caller anyway.

**Action for the integrator** when both branches land:

Add this extension to `Sources/DesignSystem/Identities/CockpitInstrument.swift`
(or a new `Categories.swift` next to it):

```swift
import SwiftUI

/// Canonical category palette — mirrors `CategoryID.displayColor` in
/// `Features/Categories/CategoryID.swift`. Kept here as a `TokenSet`
/// helper so non-Features callers (charts, instruments, the LIFE shell)
/// can read the same color without crossing module boundaries.
extension TokenSet {
    public enum CategoryPaletteID: String, Sendable, Hashable {
        case restaurants, subscriptions, groceries, loans, clothing
        case income, transfers, personalCare = "personal-care"
        case entertainment, fees, other
    }

    public func category(_ id: CategoryPaletteID) -> Color {
        switch id {
        case .restaurants:   return Color(red: 0x4C/255, green: 0xAF/255, blue: 0x6B/255)
        case .subscriptions: return Color(red: 0xA0/255, green: 0x6C/255, blue: 0xD5/255)
        case .groceries:     return Color(red: 0x7C/255, green: 0xB3/255, blue: 0x42/255)
        case .loans:         return Color(red: 0xE5/255, green: 0x39/255, blue: 0x35/255)
        case .clothing:      return Color(red: 0xEC/255, green: 0x40/255, blue: 0x7A/255)
        case .income:        return Color(red: 0x26/255, green: 0xA6/255, blue: 0x9A/255)
        case .transfers:     return Color(red: 0x42/255, green: 0xA5/255, blue: 0xF5/255)
        case .personalCare:  return Color(red: 0xFF/255, green: 0xB7/255, blue: 0x4D/255)
        case .entertainment: return Color(red: 0xFF/255, green: 0xA7/255, blue: 0x26/255)
        case .fees:          return Color(red: 0x8D/255, green: 0x6E/255, blue: 0x63/255)
        case .other:         return Color(red: 0x78/255, green: 0x90/255, blue: 0x9C/255)
        }
    }
}
```

After that lands, `CategoryID.displayColor` should be rewritten to delegate
through `TokenSet.category(_:)` so identities can override the palette
later (e.g. a high-contrast or print identity could shift these hexes
without touching the Features layer). The slug strings stay the source
of truth across the seam.

## Wire-compat with the existing `TransactionCategory`

`Models.TransactionCategory` (server string) is **not** modified by this
work. The Transaction wire shape stays:

```swift
public enum TransactionCategory: Sendable, Hashable, Codable {
    case knownCategory(String)
    case unknown
}
```

`CategoryResolver.resolve(_:)` reads `.knownCategory` (string) and rules-engines
when the string doesn't map. Existing decoders and existing call sites
(LedgerFilter, FinanceTransactionsViewModel, DemoData) continue to compile
unchanged.

## Where the pill is used

| Surface | Owner agent | How |
| ------- | ----------- | --- |
| Dashboard recent-transactions list | agent 2 | `CategoryPill(transaction: tx, size: .compact)` per row |
| Transactions ledger | (existing) | swap any inline category text for `CategoryPill(transaction: tx)` |
| Transaction inspector | (existing) | `CategoryPill(transaction: tx, size: .large)` in the header |
| Subscriptions surface | agent 4 | colored by `.subscriptions` id; subs always render that pill |
| Categories surface | this module | row preview + filtered detail (TODO M-next) |

Tap behavior on the pill is deliberately not wired here — each surface
attaches its own picker (popover on macOS, sheet on iPhone) per the
brief.
