import Foundation
import Testing
@testable import Features

/// Round-trip behavior for the [[CategoryStore]] actor — add, rename,
/// remove, and persistence across instances. Each test uses an isolated
/// UserDefaults suite so they can run in parallel without bleeding.
@Suite("CategoryStore")
struct CategoryStoreTests {

    /// Each test gets a UUID-scoped UserDefaults suite so they can run in
    /// parallel without bleeding state. The suite is wiped at the start.
    private func isolatedSuite() -> String {
        let suite = "synnapse.categorystore.tests.\(UUID().uuidString)"
        // Make sure no previous run polluted the suite.
        UserDefaults().removePersistentDomain(forName: suite)
        return suite
    }

    @Test
    func defaultsAreLoadedWithNoCustoms() async {
        let store = CategoryStore(suiteName: isolatedSuite())
        let cats = await store.categories()
        // 10 defaults + .other == 11
        #expect(cats.count == CategoryID.defaults.count)
        #expect(cats.contains(.restaurants))
        #expect(cats.contains(.other))
    }

    @Test
    func addCustomRoundTrips() async {
        let suite = isolatedSuite()
        let store = CategoryStore(suiteName: suite)
        let rec = CustomCategoryRecord(
            slug: "pets",
            displayName: "Pets",
            emoji: "🐾",
            hex: "#7B61FF"
        )
        await store.addCustom(rec)

        let after = await store.customRecords()
        #expect(after.count == 1)
        #expect(after.first?.slug == "pets")

        // New instance — same suite — should re-hydrate the custom.
        let revived = CategoryStore(suiteName: suite)
        let revivedCustoms = await revived.customRecords()
        #expect(revivedCustoms.count == 1)
        #expect(revivedCustoms.first?.displayName == "Pets")
        #expect(revivedCustoms.first?.hex == "#7B61FF")
    }

    @Test
    func renameUpdatesInPlace() async {
        let store = CategoryStore(suiteName: isolatedSuite())
        await store.addCustom(.init(slug: "pets", displayName: "Pets", emoji: "🐾", hex: "#7B61FF"))
        await store.rename(.custom(slug: "pets"), to: "Pet Care")

        let rec = await store.record(for: .custom(slug: "pets"))
        #expect(rec?.displayName == "Pet Care")
        // Slug stays stable across rename — UI never has to chase ids.
        #expect(rec?.slug == "pets")
    }

    @Test
    func removeDropsCustom() async {
        let store = CategoryStore(suiteName: isolatedSuite())
        await store.addCustom(.init(slug: "pets", displayName: "Pets", emoji: "🐾", hex: "#7B61FF"))
        #expect(await store.customRecords().count == 1)
        await store.remove(.custom(slug: "pets"))
        #expect(await store.customRecords().isEmpty)
    }

    @Test
    func duplicateSlugReplacesInPlace() async {
        let store = CategoryStore(suiteName: isolatedSuite())
        await store.addCustom(.init(slug: "pets", displayName: "Pets", emoji: "🐾", hex: "#7B61FF"))
        await store.addCustom(.init(slug: "pets", displayName: "Animals", emoji: "🐕", hex: "#4CAF6B"))
        let recs = await store.customRecords()
        #expect(recs.count == 1)
        #expect(recs.first?.displayName == "Animals")
    }

    @Test
    func categoriesReturnsDefaultsThenCustoms() async {
        let store = CategoryStore(suiteName: isolatedSuite())
        await store.addCustom(.init(slug: "pets", displayName: "Pets", emoji: "🐾", hex: "#7B61FF"))
        let cats = await store.categories()
        #expect(cats.count == CategoryID.defaults.count + 1)
        // Order is documented: defaults first, then customs.
        #expect(cats.first == CategoryID.defaults.first)
        #expect(cats.last == .custom(slug: "pets"))
    }
}

@Suite("CategoryID slug round-trip")
struct CategoryIDCodableTests {

    @Test
    func slugsAreStableForAllDefaults() throws {
        for id in CategoryID.defaults {
            let data = try JSONEncoder().encode(id)
            let decoded = try JSONDecoder().decode(CategoryID.self, from: data)
            #expect(decoded == id, "round-trip failed for \(id.slug)")
        }
    }

    @Test
    func customSlugRoundTrips() throws {
        let id: CategoryID = .custom(slug: "pets")
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(CategoryID.self, from: data)
        #expect(decoded == id)
    }

    @Test
    func unknownSlugRevivesAsCustom() throws {
        // Forward-compat: a slug we don't recognize must survive a
        // round-trip as a .custom(slug:) rather than being dropped or
        // crashing the decoder.
        let json = "\"some-unknown-future-slug\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CategoryID.self, from: json)
        if case .custom(let s) = decoded {
            #expect(s == "some-unknown-future-slug")
        } else {
            Issue.record("expected .custom for unknown slug, got \(decoded)")
        }
    }
}
