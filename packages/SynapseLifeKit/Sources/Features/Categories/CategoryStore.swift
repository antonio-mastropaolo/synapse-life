import Foundation
import SwiftUI

/// A user-added category. Default categories are *not* represented as
/// records — they live in [[CategoryID]] code and never need persistence.
/// Only customs round-trip to disk.
public struct CustomCategoryRecord: Sendable, Hashable, Codable {
    public let slug: String
    public var displayName: String
    public var emoji: String
    /// Hex string in `#RRGGBB` form. Stored as text so the persisted
    /// payload reads cleanly and so we can swap the hex parser without a
    /// schema migration.
    public var hex: String

    public init(slug: String, displayName: String, emoji: String, hex: String) {
        self.slug = slug
        self.displayName = displayName
        self.emoji = emoji
        self.hex = hex
    }

    public var displayColor: Color {
        Color(hexString: hex) ?? Color(hex: 0x78909C)
    }
}

/// Persistence-backed registry of categories. Actor-isolated because
/// custom-category writes can fire from anywhere (settings, inline picker,
/// auto-create-on-rule) and the in-memory list is the single source of
/// truth for the Categories surface and the inline picker.
///
/// `UserDefaults` is thread-safe but not `Sendable`, so the actor takes
/// a `Sendable` suite-name string (or nil for the default suite) and
/// wraps the live reference in an `@unchecked Sendable` box. The same
/// pattern is used by [[RestorationStore]] elsewhere in the kit.
public actor CategoryStore {

    public static let defaultsKey = "synapse.categories.custom.v1"

    private struct DefaultsBox: @unchecked Sendable {
        let defaults: UserDefaults
    }

    private let box: DefaultsBox
    private var customs: [CustomCategoryRecord]

    public init(suiteName: String? = nil) {
        let resolved: UserDefaults = {
            if let suiteName, let suite = UserDefaults(suiteName: suiteName) {
                return suite
            }
            return .standard
        }()
        self.box = DefaultsBox(defaults: resolved)
        if
            let data = resolved.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode([CustomCategoryRecord].self, from: data)
        {
            self.customs = decoded
        } else {
            self.customs = []
        }
    }

    // MARK: - Reads

    /// The full list shown in the Categories surface: 10 defaults +
    /// `.other` + every custom in insertion order. The view treats this
    /// as opaque — it does not assume `.other` is at the end, only that
    /// the order is stable across reads.
    public func categories() -> [CategoryID] {
        CategoryID.defaults + customs.map { CategoryID.custom(slug: $0.slug) }
    }

    public func customRecords() -> [CustomCategoryRecord] { customs }

    /// O(N) by design — N is the number of custom categories, bounded by
    /// the user's patience.
    public func record(for id: CategoryID) -> CustomCategoryRecord? {
        guard case .custom(let slug) = id else { return nil }
        return customs.first { $0.slug == slug }
    }

    // MARK: - Writes

    /// Add or overwrite a custom category. Returns the resulting record.
    /// Slug uniqueness is enforced by replacing in place rather than
    /// throwing — the UI never lets the user create two with the same
    /// slug, but the actor stays robust if the caller passes a duplicate.
    @discardableResult
    public func addCustom(_ record: CustomCategoryRecord) -> CustomCategoryRecord {
        if let idx = customs.firstIndex(where: { $0.slug == record.slug }) {
            customs[idx] = record
        } else {
            customs.append(record)
        }
        persist()
        return record
    }

    public func remove(_ id: CategoryID) {
        guard case .custom(let slug) = id else { return }
        customs.removeAll { $0.slug == slug }
        persist()
    }

    public func rename(_ id: CategoryID, to newName: String) {
        guard case .custom(let slug) = id else { return }
        guard let idx = customs.firstIndex(where: { $0.slug == slug }) else { return }
        customs[idx].displayName = newName
        persist()
    }

    // MARK: - Internal

    private func persist() {
        if let data = try? JSONEncoder().encode(customs) {
            box.defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}

// MARK: - Hex parsing for custom records

extension Color {
    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string. Returns nil for malformed
    /// input so callers can fall back to a safe default; this keeps the
    /// store from corrupting the UI on a bad value.
    public init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}
