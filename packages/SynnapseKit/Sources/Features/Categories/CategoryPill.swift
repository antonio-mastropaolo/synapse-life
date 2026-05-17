import SwiftUI
import Models

/// Pill component used everywhere a transaction is rendered.
///
/// Mirrors the Copilot reference: a rounded capsule with uppercase 9pt
/// SF Mono bold text in white over the category's deterministic color.
/// Two sizes exist for the two surfaces:
///   • `.compact` — used inline in ledger rows, alongside the merchant
///     name (height ≈ 14pt).
///   • `.large` — used in the transaction inspector / detail row
///     (height ≈ 20pt).
///
/// Tap behavior is *not* wired here. The pill stays a pure presentation
/// surface; the row/inspector wraps it in a `Button { … } label: { pill }`
/// or attaches its own `.popover` / `.sheet` for the picker. Keeping the
/// pill stateless lets the snapshot tests render it deterministically
/// without dragging in the store.
public struct CategoryPill: View {

    public enum Size: Sendable, Equatable {
        case compact
        case large
    }

    public let category: CategoryID
    public let size: Size

    /// Optional override for the rendered text. Default is `category.displayName`
    /// uppercased. Custom categories typically pass nil and let the pill
    /// uppercase the user's chosen name.
    public let labelOverride: String?

    /// Optional override for the pill background. Used by custom categories
    /// that need to pick up the user-chosen hex from `CustomCategoryRecord`.
    /// Defaults to the canonical [[CategoryID.displayColor]].
    public let colorOverride: Color?

    public init(
        category: CategoryID,
        size: Size = .compact,
        labelOverride: String? = nil,
        colorOverride: Color? = nil
    ) {
        self.category = category
        self.size = size
        self.labelOverride = labelOverride
        self.colorOverride = colorOverride
    }

    public var body: some View {
        Text(displayText)
            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.white)
            .tracking(0.4)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(colorOverride ?? category.displayColor)
            .clipShape(Capsule(style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(displayText))
            .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - Geometry

    private var displayText: String {
        let raw = labelOverride ?? category.displayName
        return raw.uppercased()
    }

    private var fontSize: CGFloat {
        switch size {
        case .compact: return 9
        case .large:   return 11
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact: return 6
        case .large:   return 9
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact: return 2.5
        case .large:   return 4
        }
    }
}

// MARK: - Convenience

extension CategoryPill {
    /// Render a pill for a Transaction directly. Wires `CategoryResolver`
    /// internally so the ledger row only has to pass the model. The
    /// fully-qualified `Models.Transaction` is used to avoid a name
    /// collision with `SwiftUI.Transaction`.
    public init(transaction: Models.Transaction, size: Size = .compact) {
        self.init(
            category: CategoryResolver.resolve(transaction),
            size: size
        )
    }
}
