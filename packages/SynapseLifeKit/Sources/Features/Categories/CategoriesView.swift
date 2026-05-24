import SwiftUI
import Models
import DesignSystem

/// Categories surface. Mirrors the Copilot screenshot: section title at
/// the top, a list of rows (pill preview + name + emoji on the left,
/// this-month spend + tiny sparkline on the right), a "+ New category"
/// button anchored at the bottom.
///
/// macOS and iOS share the row component but differ in chrome:
///   • macOS — flat ScrollView + LazyVStack, matching the rest of the
///     Cockpit Dense shell. No grouped insets.
///   • iOS — grouped `List` so it sits naturally inside a navigation
///     stack with `.searchable` later.
@MainActor
public struct CategoriesView: View {

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @Bindable private var viewModel: CategoriesViewModel
    @State private var showingNewCategorySheet = false

    public init(viewModel: CategoriesViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        #if os(macOS)
        macLayout
        #else
        iosLayout
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return VStack(spacing: 0) {
            header(tokens: tokens)
            Divider().background(tokens.foregroundSecondary.color.opacity(0.18))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        CategoryListRow(row: row, tokens: tokens)
                        Divider().background(tokens.foregroundSecondary.color.opacity(0.10))
                    }
                    newCategoryButton(tokens: tokens)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(tokens.background.color)
        .navigationTitle("Categories")
        .sheet(isPresented: $showingNewCategorySheet) {
            NewCategorySheet { _ in
                showingNewCategorySheet = false
            }
        }
    }
    #endif

    // MARK: - iOS

    #if !os(macOS)
    private var iosLayout: some View {
        let tokens = theme.tokens(for: scheme)
        return List {
            Section {
                ForEach(viewModel.rows) { row in
                    CategoryListRow(row: row, tokens: tokens)
                        .listRowBackground(tokens.surface.color)
                }
            }
            Section {
                Button {
                    showingNewCategorySheet = true
                } label: {
                    Label("New category", systemImage: "plus.circle.fill")
                        .foregroundStyle(tokens.accent.color)
                }
                .listRowBackground(tokens.surface.color)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(tokens.background.color)
        .navigationTitle("Categories")
        .sheet(isPresented: $showingNewCategorySheet) {
            NewCategorySheet { _ in
                showingNewCategorySheet = false
            }
        }
    }
    #endif

    // MARK: - Pieces

    private func header(tokens: TokenSet) -> some View {
        HStack {
            Text("Categories")
                .font(Tokens.headerFont(size: 18, weight: .semibold).swiftUIFont)
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tokens.background.color)
    }

    private func newCategoryButton(tokens: TokenSet) -> some View {
        Button {
            showingNewCategorySheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("New category")
                    .font(Tokens.tickerFont(size: 11, weight: .semibold).swiftUIFont)
            }
            .foregroundStyle(tokens.accent.color)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// Single row in the Categories list. Composes the pill, the emoji, the
/// name, this-month spend (right-aligned), and a 24pt sparkline.
@MainActor
struct CategoryListRow: View {
    let row: CategoryRow
    let tokens: TokenSet

    var body: some View {
        HStack(spacing: 12) {
            CategoryPill(category: row.id, size: .compact)
                .frame(minWidth: 96, alignment: .leading)
            Text(row.emoji)
                .font(.system(size: 14))
            Text(row.displayName)
                .font(Tokens.tickerFont(size: 12, weight: .semibold).swiftUIFont)
                .foregroundStyle(tokens.foregroundPrimary.color)
            Spacer()
            sparkline
                .frame(width: 60, height: 18)
            Text(formatMoney(row.spend))
                .font(Tokens.tickerFont(size: 12).swiftUIFont)
                .foregroundStyle(tokens.foregroundPrimary.color)
                .monospacedDigit()
                .frame(minWidth: 88, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tokens.surface.color)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(row.displayName), \(formatMoney(row.spend)) this month"))
    }

    private var sparkline: some View {
        GeometryReader { geo in
            let values = row.spark
            let maxV = max(values.max() ?? 0, 0.0001)
            Path { p in
                guard values.count > 1 else { return }
                let step = geo.size.width / CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let x = CGFloat(i) * step
                    let normalized = v / maxV
                    let y = geo.size.height * (1.0 - CGFloat(normalized))
                    if i == 0 {
                        p.move(to: CGPoint(x: x, y: y))
                    } else {
                        p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(row.id.displayColor, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func formatMoney(_ d: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSDecimalNumber(decimal: d)) ?? "$0.00"
    }
}

/// Sheet for creating a custom category. Minimal — name, emoji, color
/// hex. The full color/emoji pickers are intentionally simple here
/// because the integrator may swap them for the project-standard
/// pickers later. The shape (name + emoji + hex) is the contract.
@MainActor
struct NewCategorySheet: View {
    var onDismiss: (CustomCategoryRecord?) -> Void

    @State private var name: String = ""
    @State private var emoji: String = "🏷️"
    @State private var hex: String = "#42A5F5"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New category")
                .font(.system(size: 16, weight: .semibold))
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                TextField("Emoji", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                TextField("Color (hex)", text: $hex)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Cancel") { onDismiss(nil) }
                Spacer()
                Button("Create") {
                    let slug = name
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "-")
                        .filter { $0.isLetter || $0.isNumber || $0 == "-" }
                    guard !slug.isEmpty else { onDismiss(nil); return }
                    let rec = CustomCategoryRecord(
                        slug: slug,
                        displayName: name,
                        emoji: emoji,
                        hex: hex
                    )
                    onDismiss(rec)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}
