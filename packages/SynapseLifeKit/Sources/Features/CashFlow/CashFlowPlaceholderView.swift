import SwiftUI
import DesignSystem

/// Rich placeholder for the Cash Flow surface. Stands in until the
/// real Cash Flow VM + per-month reducer + per-category breakdown
/// land. Renders a hero header card (income/expense/net for the
/// current month), a 6-month bar chart, and a per-category spend
/// breakdown with horizontal progress bars.
///
/// Every figure is sample data; the banner makes that unmistakable.
@MainActor
public struct CashFlowPlaceholderView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        let tokens = theme.tokens(for: scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header(tokens: tokens)
                sampleBanner(tokens: tokens)
                heroSummary(tokens: tokens)
                monthlyBars(tokens: tokens)
                categoryBreakdown(tokens: tokens)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tokens.background.color)
    }

    private func header(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cash flow")
                .font(.system(size: 28, weight: .semibold, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Text("Income vs expenses over time. The bar chart compares the last six months side-by-side.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    private func sampleBanner(tokens: TokenSet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("Sample cash flow — your real income and expenses will appear here once accounts are connected.")
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func heroSummary(tokens: TokenSet) -> some View {
        HStack(spacing: 14) {
            kpiCard(
                label: "Income this month",
                value: "$3,460",
                accent: Color(red: 0.34, green: 0.78, blue: 0.50),
                tokens: tokens
            )
            kpiCard(
                label: "Expenses this month",
                value: "$2,178",
                accent: Color(red: 0.93, green: 0.46, blue: 0.34),
                tokens: tokens
            )
            kpiCard(
                label: "Net this month",
                value: "+$1,282",
                accent: Color(red: 1.00, green: 0.69, blue: 0.22),
                tokens: tokens
            )
        }
    }

    private func kpiCard(label: String, value: String, accent: Color, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(tokens.foregroundSecondary.color)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.foregroundSecondary.color.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func monthlyBars(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LAST 6 MONTHS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)

            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Self.monthlyData) { m in
                    monthBar(m, tokens: tokens)
                }
            }
            .frame(height: 180)
            .padding(.vertical, 4)

            // Legend
            HStack(spacing: 18) {
                legendSwatch(color: Color(red: 0.34, green: 0.78, blue: 0.50), label: "Income", tokens: tokens)
                legendSwatch(color: Color(red: 0.93, green: 0.46, blue: 0.34), label: "Expenses", tokens: tokens)
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
    }

    private func monthBar(_ m: MonthBucket, tokens: TokenSet) -> some View {
        let maxVal: Double = 4000
        let incomeH = CGFloat(min(m.income / maxVal, 1.0)) * 150
        let expenseH = CGFloat(min(m.expenses / maxVal, 1.0)) * 150
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.34, green: 0.78, blue: 0.50))
                    .frame(width: 14, height: incomeH)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.93, green: 0.46, blue: 0.34))
                    .frame(width: 14, height: expenseH)
            }
            .frame(height: 150, alignment: .bottom)

            Text(m.label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    private func legendSwatch(color: Color, label: String, tokens: TokenSet) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.foregroundSecondary.color)
        }
    }

    private func categoryBreakdown(tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SPEND BY CATEGORY · THIS MONTH")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(tokens.foregroundSecondary.color)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.categories) { c in
                    categoryRow(c, tokens: tokens)
                    Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tokens.surface.color)
        )
    }

    private func categoryRow(_ c: CategorySpend, tokens: TokenSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(c.color).frame(width: 8, height: 8)
                    Text(c.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tokens.foregroundPrimary.color)
                }
                Spacer()
                Text("$\(c.amount)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(tokens.foregroundPrimary.color)
            }
            GeometryReader { geo in
                let total = max(Self.categories.map(\.amount).max() ?? 1, 1)
                let w = geo.size.width * CGFloat(c.amount) / CGFloat(total)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(c.color.opacity(0.14))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(c.color.opacity(0.85))
                        .frame(width: w)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Sample data

    private struct MonthBucket: Identifiable {
        let id = UUID()
        let label: String
        let income: Double
        let expenses: Double
    }

    private static let monthlyData: [MonthBucket] = [
        MonthBucket(label: "DEC", income: 3200, expenses: 2300),
        MonthBucket(label: "JAN", income: 3460, expenses: 1980),
        MonthBucket(label: "FEB", income: 3460, expenses: 2410),
        MonthBucket(label: "MAR", income: 3460, expenses: 2150),
        MonthBucket(label: "APR", income: 3700, expenses: 2380),
        MonthBucket(label: "MAY", income: 3460, expenses: 2178)
    ]

    private struct CategorySpend: Identifiable {
        let id = UUID()
        let name: String
        let amount: Int
        let color: Color
    }

    private static let categories: [CategorySpend] = [
        .init(name: "Sample Restaurants",   amount: 612, color: Color(red: 0.30, green: 0.69, blue: 0.42)),
        .init(name: "Sample Groceries",     amount: 482, color: Color(red: 0.49, green: 0.70, blue: 0.26)),
        .init(name: "Sample Loans",         amount: 340, color: Color(red: 0.90, green: 0.22, blue: 0.21)),
        .init(name: "Sample Subscriptions", amount: 188, color: Color(red: 0.63, green: 0.42, blue: 0.84)),
        .init(name: "Sample Clothing",      amount: 156, color: Color(red: 0.93, green: 0.25, blue: 0.48)),
        .init(name: "Sample Transport",     amount: 124, color: Color(red: 0.26, green: 0.65, blue: 0.96)),
        .init(name: "Sample Entertainment", amount: 96,  color: Color(red: 1.00, green: 0.66, blue: 0.15)),
        .init(name: "Sample Personal Care", amount: 88,  color: Color(red: 1.00, green: 0.72, blue: 0.30)),
        .init(name: "Sample Fees",          amount: 22,  color: Color(red: 0.55, green: 0.43, blue: 0.39))
    ]
}
