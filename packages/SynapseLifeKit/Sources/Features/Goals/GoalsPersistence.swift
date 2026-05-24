import Foundation

/// JSON-on-disk persistence for the Goals store. Lives in Application
/// Support so it survives caches purges. Schema-versioned filename so
/// future migrations are a one-line rename rather than a destructive
/// in-place upgrade.
public struct GoalsPersistence: Sendable {
    public static let `default` = GoalsPersistence()

    private let fileName = "goals.v1.json"

    public init() {}

    public func load() throws -> [Goal] {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Goal].self, from: data)
    }

    public func save(_ goals: [Goal]) throws {
        let url = try fileURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(goals)
        try data.write(to: url, options: .atomic)
    }

    private func fileURL() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Synapse", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }
}
