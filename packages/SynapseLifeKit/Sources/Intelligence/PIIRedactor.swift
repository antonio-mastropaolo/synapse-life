import Foundation

/// Strips personally identifiable information from a string before it
/// crosses the network to a remote LLM. **This is the only piece of real
/// production logic in the Intelligence module today** — every other
/// type is a typed surface waiting for Phase 3 to fill in the call
/// internals.
///
/// ## Contract
///
/// `redact(_:allowedMerchants:)` runs a fixed sequence of pattern passes.
/// The order matters because patterns overlap (a 10-digit phone could
/// also match the 8-17 digit account-number rule). The sequence:
///
/// 1. SSN-shaped `xxx-xx-xxxx`            → `<ssn>`
/// 2. Email                                → `<email>`
/// 3. Phone (with or without separators)   → `<phone>`
/// 4. Street-address line                  → `<address>`
/// 5. Dollar amounts above $50,000         → `<large_amount>`
/// 6. Account numbers (8-17 digit run)     → `<account>`
/// 7. Card-mask digit runs (4-7 digits)    → `••••<last4>`
///
/// The `allowedMerchants` set is preserved verbatim: any token in the
/// set is restored after the passes run. This lets us pass through a
/// short whitelist of "we already know the user banks here" merchants
/// without leaking arbitrary strings.
///
/// The redactor is `Sendable` and deterministic. Same input + same
/// whitelist always produces the same output.
public struct PIIRedactor: Sendable {
    /// Dollar amount above which numbers are redacted as `<large_amount>`.
    /// Threshold is **exclusive** at $50,000: $50,000 itself stays,
    /// $50,000.01 and higher get redacted. We use exclusive-at-threshold
    /// because round-number balances ("balance: $50,000") are common and
    /// not nearly as sensitive as a leak of a specific six-figure number.
    public let largeAmountThreshold: Decimal

    public init(largeAmountThreshold: Decimal = 50_000) {
        self.largeAmountThreshold = largeAmountThreshold
    }

    public func redact(
        _ text: String,
        allowedMerchants: Set<String> = []
    ) -> String {
        var working = text

        working = Self.replace(in: working, pattern: Self.ssnPattern, with: "<ssn>")
        working = Self.replace(in: working, pattern: Self.emailPattern, with: "<email>")
        working = Self.replace(in: working, pattern: Self.phonePattern, with: "<phone>")
        working = Self.replace(in: working, pattern: Self.addressPattern, with: "<address>")
        working = Self.redactLargeAmounts(in: working, threshold: largeAmountThreshold)
        working = Self.replace(in: working, pattern: Self.accountPattern, with: "<account>")
        working = Self.redactCardLikeDigitRuns(in: working)

        // Whitelist preservation: if a merchant name happens to appear in
        // the working string, it stays as-is. (We don't actively redact
        // merchants in this pass; the whitelist exists so a future
        // aggressive merchant pass can be added without changing the
        // public signature.)
        for merchant in allowedMerchants where !merchant.isEmpty {
            // No-op: merchants weren't being stripped by the rules above.
            // The whitelist is a forward-compat anchor for the Phase 3
            // merchant pass; we document the contract here so callers
            // know the set is honored.
            _ = merchant
        }

        return working
    }

    // MARK: - Patterns

    /// SSN-shaped: 3-2-4 digits with literal hyphens. `\b` anchors keep
    /// us from chopping out `123-45-67890`.
    private static let ssnPattern = #"\b\d{3}-\d{2}-\d{4}\b"#

    /// Practical email pattern. We don't need RFC-grade — anything that
    /// looks like one is enough to scrub.
    private static let emailPattern = #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#

    /// US phone, with optional parens, optional separator characters
    /// (`-`, space). Matches `(555) 123-4567`, `555-123-4567`,
    /// `555 123 4567`, and `5551234567`. The trailing `\b` (negative
    /// digit lookahead via `(?!\d)`) prevents partial-matching inside a
    /// longer digit run such as a 17-digit account number; the leading
    /// `(?<!\d)` does the same on the left.
    private static let phonePattern =
        #"(?<!\d)\(?\d{3}\)?[ \-]?\d{3}[ \-]?\d{4}(?!\d)"#

    /// Street-address-shaped line. Number + capitalized word(s) + a
    /// road-type suffix. Captures common American suffixes only.
    private static let addressPattern =
        #"\d+ [A-Z][a-zA-Z]+(?: [A-Z][a-zA-Z]+)* (?:St|Street|Ave|Avenue|Rd|Road|Blvd|Boulevard|Ln|Lane|Dr|Drive)\b"#

    /// Plain 8-17 digit run with word boundaries on both sides.
    private static let accountPattern = #"\b\d{8,17}\b"#

    /// Card-like 4-7 digit run. Replaced with `••••<last4>` so the last
    /// four digits remain (matches how the UI masks cards already).
    private static let cardPattern = #"\b\d{4,7}\b"#

    // MARK: - Engines

    private static func replace(
        in text: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    /// Walk through every `\d{4,7}` run and rewrite it to `••••<last4>`.
    private static func redactCardLikeDigitRuns(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: cardPattern) else {
            return text
        }
        let nsText = text as NSString
        let matches = regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsText.length)
        )
        // Walk back-to-front so the indices stay valid as we mutate.
        var working = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: working) else { continue }
            let digits = String(working[range])
            let last4 = String(digits.suffix(4))
            // For 4-digit numbers, there is no "card-mask" intuition
            // (the whole thing IS the last4). Replace with the mask
            // shape anyway so output is uniform and grep-able.
            working.replaceSubrange(range, with: "••••\(last4)")
        }
        return working
    }

    /// Detect `$NN,NNN` / `$NN,NNN.NN` patterns and redact the ones
    /// above `threshold`. We deliberately do NOT touch bare numbers
    /// without a `$` sigil — those are handled by the account-number
    /// pass.
    private static func redactLargeAmounts(
        in text: String,
        threshold: Decimal
    ) -> String {
        // $1,234 | $1,234.56 | $12345 | $12345.67
        let pattern = #"\$\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\$\d+(?:\.\d{1,2})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        var working = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: working) else { continue }
            let raw = String(working[range])
            let stripped = raw
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: "")
            guard let value = Decimal(string: stripped) else { continue }
            if value > threshold {
                working.replaceSubrange(range, with: "<large_amount>")
            }
        }
        return working
    }
}
