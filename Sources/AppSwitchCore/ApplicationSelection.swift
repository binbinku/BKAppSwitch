import Foundation

public struct TrackedApplication: Codable, Equatable, Identifiable {
    public static let vscodeBundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss"
    ]
    public let bundleIdentifier: String
    public var name: String
    public var path: String
    public var isEnabled: Bool
    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, name: String, path: String, isEnabled: Bool = true) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
    }
}

public struct ApplicationSelection: Codable, Equatable {
    public private(set) var applications: [TrackedApplication]
    public var enabledBundleIDs: Set<String> {
        Set(applications.filter(\.isEnabled).map(\.bundleIdentifier))
    }

    public init(_ applications: [TrackedApplication] = []) {
        var seen = Set<String>()
        self.applications = applications.filter {
            !$0.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && seen.insert($0.id).inserted
        }
    }

    public mutating func add(_ application: TrackedApplication) {
        guard !application.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var enabled = application
        enabled.isEnabled = true
        if let index = applications.firstIndex(where: { $0.id == application.id }) {
            applications[index] = enabled
        } else {
            applications.append(enabled)
        }
    }

    public mutating func setEnabled(_ enabled: Bool, for id: String) {
        guard let index = applications.firstIndex(where: { $0.id == id }) else { return }
        applications[index].isEnabled = enabled
    }

    public mutating func remove(_ id: String) { applications.removeAll { $0.id == id } }

    private enum CodingKeys: String, CodingKey { case applications }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode([TrackedApplication].self, forKey: .applications))
    }
}
