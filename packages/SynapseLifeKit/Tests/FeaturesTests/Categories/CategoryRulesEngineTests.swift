import Foundation
import Testing
@testable import Features

/// Default-rule coverage tests. Every default category must match at
/// least 4 example merchants, and ambiguous strings (containing keywords
/// from multiple categories) must resolve deterministically per the
/// declared priority order in [[CategoryRulesEngine.defaultRules]].
@Suite("CategoryRulesEngine")
struct CategoryRulesEngineTests {

    @Test
    func restaurantsCoverage() {
        for s in [
            "PANERA BREAD #2914",
            "CHIPOTLE 0341 ARLINGTON",
            "STARBUCKS STORE #882",
            "SHAKE SHACK 1234",
            "MCDONALDS F9921",
            "DOORDASH*BLUE BOTTLE",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .restaurants, "expected restaurants for \(s)")
        }
    }

    @Test
    func subscriptionsCoverage() {
        for s in [
            "NETFLIX.COM",
            "Spotify USA",
            "ANTHROPIC PBC",
            "OPENAI *CHATGPT SUBSCR",
            "APPLE.COM/BILL",
            "NYTIMES Digital",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .subscriptions, "expected subscriptions for \(s)")
        }
    }

    @Test
    func groceriesCoverage() {
        for s in [
            "WHOLE FOODS MKT 10246",
            "TRADER JOE'S #538",
            "KROGER 0871",
            "WEGMANS FOOD",
            "SAFEWAY 1234",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .groceries, "expected groceries for \(s)")
        }
    }

    @Test
    func loansCoverage() {
        for s in [
            "AFFIRM*PURCHASE",
            "KLARNA PAYMENT",
            "BREAD FINANCIAL",
            "SOFI Student Loan",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .loans, "expected loans for \(s)")
        }
    }

    @Test
    func clothingCoverage() {
        for s in [
            "NIKE.COM 800-806-6453",
            "ADIDAS US",
            "ZARA #4421",
            "UNIQLO USA",
            "H&M ONLINE",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .clothing, "expected clothing for \(s)")
        }
    }

    @Test
    func incomeCoverage() {
        for s in [
            "PAYROLL DEPOSIT",
            "ACH CREDIT EMPLOYER",
            "DIRECT DEP COMPANY",
            "SALARY APRIL",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .income, "expected income for \(s)")
        }
    }

    @Test
    func transfersCoverage() {
        for s in [
            "ZELLE PAYMENT FROM A",
            "VENMO CASHOUT",
            "Cash App *FRIEND",
            "TRANSFER FROM SAVINGS",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .transfers, "expected transfers for \(s)")
        }
    }

    @Test
    func personalCareCoverage() {
        for s in [
            "GOLD'S GYM #221",
            "SUPERCUTS",
            "HAIR SALON DOWNTOWN",
            "Massage Therapy Inc",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .personalCare, "expected personalCare for \(s)")
        }
    }

    @Test
    func entertainmentCoverage() {
        for s in [
            "AMC THEATERS",
            "SIRIUSXM SATELLITE",
            "STEAM *PURCHASE",
            "XBOX LIVE GOLD",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .entertainment, "expected entertainment for \(s)")
        }
    }

    @Test
    func feesCoverage() {
        for s in [
            "OVERDRAFT FEE",
            "WIRE FEE",
            "ATM FEE",
            "FOREIGN TRANSACTION FEE",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .fees, "expected fees for \(s)")
        }
    }

    @Test
    func uncategorizedFallsThroughToOther() {
        for s in [
            "WAWA #341",                  // not in any default table
            "RANDOM LOCAL BUSINESS LLC",
            "UNKNOWN MERCHANT 99",
        ] {
            #expect(CategoryRulesEngine.categorize(s) == .other, "expected other for \(s)")
        }
    }

    // MARK: - Priority / disambiguation

    @Test
    func ambiguousPayrollWinsOverTransfer() {
        // Line that could match both Income (PAYROLL) and Transfers
        // (TRANSFER). Income lives before Transfers in the table so
        // Income must win.
        let s = "PAYROLL TRANSFER FROM EMPLOYER"
        #expect(CategoryRulesEngine.categorize(s) == .income)
    }

    @Test
    func ambiguousNetflixWinsOverEntertainment() {
        // Subscriptions table includes NETFLIX explicitly; the
        // Entertainment table doesn't list streaming brands, so this
        // tests that the literal NETFLIX token routes to subscriptions
        // even when surrounding text mentions a movie.
        let s = "NETFLIX MOVIE NIGHT"
        #expect(CategoryRulesEngine.categorize(s) == .subscriptions)
    }

    @Test
    func zelleMemoLandsTransfer() {
        // Bare ZELLE memo with no category-keyword nearby. This
        // asserts Transfers fires when nothing else has a hit — i.e.
        // the table doesn't over-match a generic memo to an earlier
        // bucket. (We deliberately do NOT mention any merchant token
        // here; the earlier tables would steal a memo containing
        // "coffee", "starbucks", etc., which is the intended product
        // behavior — a Zelle with a "STARBUCKS" memo is genuinely a
        // food purchase from the user's perspective.)
        let s = "ZELLE PAYMENT MEMO rent share"
        #expect(CategoryRulesEngine.categorize(s) == .transfers)
    }

    @Test
    func feeKeywordDoesNotHijackMerchant() {
        // A merchant whose name happens to contain "free" must not be
        // misrouted to Fees. We use the word-boundary anchor in the
        // pattern so this stays robust.
        let s = "FREE PEOPLE STORE 0294"
        #expect(CategoryRulesEngine.categorize(s) != .fees)
    }
}
