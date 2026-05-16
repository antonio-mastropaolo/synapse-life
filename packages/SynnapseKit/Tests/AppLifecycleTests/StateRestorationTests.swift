import Foundation
import Testing
@testable import AppLifecycle

@Suite("State restoration payload")
struct StateRestorationTests {

    @Test("payload round-trips through JSON identically")
    func roundTrip() throws {
        let payload = RestorationPayload(
            sidebarSelection: "approvals",
            macWindow: .init(width: 1280, height: 800),
            iosLastTab: "finance",
            spotlightQuery: "llm judge",
            financeSurface: "personal"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(RestorationPayload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("missing fields decode to nil — forward-compat downward")
    func partialDecode() throws {
        let json = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(RestorationPayload.self, from: json)
        #expect(decoded.sidebarSelection == nil)
        #expect(decoded.macWindow == nil)
        #expect(decoded.iosLastTab == nil)
        #expect(decoded.spotlightQuery == nil)
        #expect(decoded.financeSurface == nil)
    }

    @Test("unknown fields are ignored — forward-compat upward")
    func unknownFieldsIgnored() throws {
        // A future version of the app might add a field; the current
        // decoder must not throw when it sees one. Codable's default
        // behaviour ignores unknown keys, but we still pin it as a
        // contract.
        let json = Data("""
        {
          "sidebarSelection": "life",
          "macWindow": { "width": 1024, "height": 720 },
          "iosLastTab": null,
          "spotlightQuery": null,
          "financeSurface": "accounts",
          "futureKnob": { "thing": true, "count": 7 },
          "anotherKnob": "stranger"
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(RestorationPayload.self, from: json)
        #expect(decoded.sidebarSelection == "life")
        #expect(decoded.financeSurface == "accounts")
        let window = try #require(decoded.macWindow)
        #expect(window.width == 1024)
        #expect(window.height == 720)
    }

    @Test("RestorationStore persists and loads via UserDefaults")
    func storeRoundTrip() async throws {
        let suiteName = "synnapse.tests.restoration.\(UUID().uuidString)"
        defer {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }

        let store = RestorationStore(suiteName: suiteName)
        let payload = RestorationPayload(
            sidebarSelection: "spotlight",
            macWindow: .init(width: 1440, height: 900),
            iosLastTab: "life",
            spotlightQuery: "vector db",
            financeSurface: "investments"
        )
        await store.save(payload)
        let loaded = await store.load()
        #expect(loaded == payload)
    }

    @Test("load returns nil when nothing has been saved")
    func emptyLoad() async throws {
        let suiteName = "synnapse.tests.restoration.\(UUID().uuidString)"
        defer {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }

        let store = RestorationStore(suiteName: suiteName)
        let loaded = await store.load()
        #expect(loaded == nil)
    }

    @Test("clear removes the persisted payload")
    func clear() async throws {
        let suiteName = "synnapse.tests.restoration.\(UUID().uuidString)"
        defer {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }

        let store = RestorationStore(suiteName: suiteName)
        await store.save(RestorationPayload(sidebarSelection: "x"))
        await store.clear()
        let loaded = await store.load()
        #expect(loaded == nil)
    }
}
