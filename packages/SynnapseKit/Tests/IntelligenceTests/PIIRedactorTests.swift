import XCTest
@testable import Intelligence

final class PIIRedactorTests: XCTestCase {
    private let r = PIIRedactor()

    // MARK: - Email

    func test_email_basic() {
        XCTAssertEqual(
            r.redact("Email me at user@example.com please"),
            "Email me at <email> please"
        )
    }

    func test_email_with_plus_and_dots() {
        XCTAssertEqual(
            r.redact("First.Last+tag@sub.example.co"),
            "<email>"
        )
    }

    func test_email_two_addresses_in_one_string() {
        let out = r.redact("a@b.io and c@d.org")
        XCTAssertEqual(out, "<email> and <email>")
    }

    // MARK: - Phone

    func test_phone_with_parens() {
        XCTAssertEqual(
            r.redact("Call (555) 123-4567 now"),
            "Call <phone> now"
        )
    }

    func test_phone_dashes() {
        XCTAssertEqual(
            r.redact("555-123-4567"),
            "<phone>"
        )
    }

    func test_phone_no_separators() {
        XCTAssertEqual(
            r.redact("5551234567"),
            "<phone>"
        )
    }

    func test_phone_with_spaces() {
        XCTAssertEqual(
            r.redact("555 123 4567"),
            "<phone>"
        )
    }

    // MARK: - SSN

    func test_ssn_basic() {
        XCTAssertEqual(
            r.redact("SSN 123-45-6789 on file"),
            "SSN <ssn> on file"
        )
    }

    func test_ssn_not_matching_phone_shape() {
        // 555-12-3456 has 3-2-4 digits, matches SSN, should be ssn.
        XCTAssertEqual(
            r.redact("555-12-3456"),
            "<ssn>"
        )
    }

    // MARK: - Account number

    func test_account_eight_digit() {
        XCTAssertEqual(
            r.redact("Account 12345678 active"),
            "Account <account> active"
        )
    }

    func test_account_seventeen_digit() {
        XCTAssertEqual(
            r.redact("Routing 12345678901234567 done"),
            "Routing <account> done"
        )
    }

    // MARK: - Card-like masks (4-7 digits)

    func test_card_last4_kept() {
        XCTAssertEqual(
            r.redact("Card ending 4242"),
            "Card ending ••••4242"
        )
    }

    func test_card_six_digit_masked() {
        XCTAssertEqual(
            r.redact("Token 123456 used"),
            "Token ••••3456 used"
        )
    }

    // MARK: - Address

    func test_address_basic_street() {
        XCTAssertEqual(
            r.redact("Lives at 123 Main Street here"),
            "Lives at <address> here"
        )
    }

    func test_address_avenue_abbrev() {
        XCTAssertEqual(
            r.redact("742 Evergreen Ave is famous"),
            "<address> is famous"
        )
    }

    func test_address_two_word_name() {
        XCTAssertEqual(
            r.redact("221 Baker Street"),
            "<address>"
        )
    }

    // MARK: - Large amount threshold

    func test_amount_below_threshold_stays() {
        // $49,999 is below the $50,000 cutoff and stays verbatim.
        XCTAssertEqual(
            r.redact("Balance $49,999"),
            "Balance $49,999"
        )
    }

    func test_amount_at_threshold_stays() {
        // Threshold is exclusive at $50,000 — equal stays.
        XCTAssertEqual(
            r.redact("Balance $50,000"),
            "Balance $50,000"
        )
    }

    func test_amount_just_above_threshold_redacted() {
        XCTAssertEqual(
            r.redact("Balance $50,001"),
            "Balance <large_amount>"
        )
    }

    func test_amount_large_six_figure_redacted() {
        XCTAssertEqual(
            r.redact("Bought house for $725,000"),
            "Bought house for <large_amount>"
        )
    }

    func test_amount_small_unaffected() {
        XCTAssertEqual(
            r.redact("Coffee $4.50"),
            "Coffee $4.50"
        )
    }

    // MARK: - Mixed PII paragraph

    func test_mixed_paragraph() {
        // Note: phone is parenthesized + space-separated so it can't
        // collide with the account-number pass; account is 8 digits so
        // it can't be mistaken for a 10-digit phone.
        let input = "John (555) 123-4567 emailed jdoe@example.com from 100 Main Street about a $250,000 loan; SSN 123-45-6789, account 98765432."
        let out = r.redact(input)
        XCTAssertTrue(out.contains("<phone>"), out)
        XCTAssertTrue(out.contains("<email>"), out)
        XCTAssertTrue(out.contains("<address>"), out)
        XCTAssertTrue(out.contains("<large_amount>"), out)
        XCTAssertTrue(out.contains("<ssn>"), out)
        XCTAssertTrue(out.contains("<account>"), out)
        XCTAssertFalse(out.contains("jdoe"), out)
        XCTAssertFalse(out.contains("555"), out)
    }

    // MARK: - Edge cases

    func test_empty_input() {
        XCTAssertEqual(r.redact(""), "")
    }

    func test_input_with_no_pii_unchanged() {
        let s = "Hello world, this string has nothing sensitive."
        XCTAssertEqual(r.redact(s), s)
    }

    func test_amount_with_cents_above_threshold() {
        XCTAssertEqual(
            r.redact("Wired $99,999.99"),
            "Wired <large_amount>"
        )
    }

    // MARK: - Merchant whitelist

    func test_whitelisted_merchant_preserved() {
        // Starbucks is whitelisted; $4.50 is well below threshold; both
        // should pass through unchanged.
        XCTAssertEqual(
            r.redact("Coffee at Starbucks for $4.50", allowedMerchants: ["Starbucks"]),
            "Coffee at Starbucks for $4.50"
        )
    }

    func test_whitelisted_merchant_kept_when_amount_redacted() {
        // The merchant survives even if other rules in the same string
        // do trigger.
        let out = r.redact(
            "Bought concert tickets at Starbucks for $75,000",
            allowedMerchants: ["Starbucks"]
        )
        XCTAssertTrue(out.contains("Starbucks"), out)
        XCTAssertTrue(out.contains("<large_amount>"), out)
    }
}
