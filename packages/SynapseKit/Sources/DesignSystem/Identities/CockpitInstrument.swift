import SwiftUI

/// Finance-specific extension points for the CockpitInstrument identity.
///
/// M5 promoted the CockpitInstrument identity to the Finance surface and
/// added three tokens to `TokenSet` (gain/loss accents and a ledger stripe).
/// Those tokens live on every `TokenSet` so the type system stays uniform,
/// but their values are tuned in `Tokens.cockpitInstrumentLight`.
///
/// This file holds the typography helpers that are specific to the
/// instrument language: a monospaced ticker font for prices and a uniform
/// ledger-row font. They live on `TokenSet` as functions so callers don't
/// have to thread Identity through every chart and table.
extension TokenSet {

    /// Monospaced typeface used for prices, tickers, and balance digits. The
    /// instrument identity expects tabular numerals so columns line up
    /// without manual padding.
    public func tickerFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
            .monospacedDigit()
    }

    /// Compact ledger row font. Same monospaced design at the standard 11pt
    /// ledger size, used by the transactions table and per-account rows.
    public var ledgerRowFont: Font {
        tickerFont(size: 11, weight: .regular)
    }
}
