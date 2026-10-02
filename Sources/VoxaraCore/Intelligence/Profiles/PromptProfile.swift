import Foundation

/// A destination-specific prompt style, loaded from JSON so it can be edited without recompiling.
public struct PromptProfile: Codable, Sendable, Equatable, Identifiable {
    public struct Style: Codable, Sendable, Equatable {
        /// "colon" → `Requirements:`, "markdown" → `## Requirements`, "xml" → `<requirements>…</requirements>`.
        public var heading: String
        public var numberedWorkflow: Bool
    }

    /// A rule that adds a standard line only when the transcript contains one of its trigger phrases.
    /// This is how implied-but-unstated workflow expectations are added without inventing facts.
    public struct Signal: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var triggers: [String]
        public var section: String
        public var text: [String: String]
        public var presets: [String]
    }

    public var id: String
    public var name: String
    public var version: Int
    public var philosophy: String
    public var style: Style
    public var sectionOrder: [String]
    public var labels: [String: [String: String]]
    public var signals: [Signal]
    public var forbidden: [String]
    public var extractorHints: String

    public func label(_ section: String, language: String) -> String {
        labels[language]?[section] ?? labels["en"]?[section] ?? section.capitalized
    }
}

public struct PresetConfig: Codable, Sendable, Equatable {
    public var sections: [String]
    public var signals: Bool
    public var compact: Bool
    public var numberWorkflow: Bool?
}

struct PresetFile: Codable { var version: Int; var presets: [String: PresetConfig] }

public enum ProfileError: LocalizedError {
    case missingBundle
    public var errorDescription: String? { "Bundled prompt profiles could not be found." }
}

/// Loads bundled profiles, then lets files in `~/Library/Application Support/Voxara/PromptProfiles` override them by id.
public struct ProfileStore: Sendable {
    public private(set) var profiles: [String: PromptProfile]
    public private(set) var presets: [PromptPreset: PresetConfig]

    public static let profileOrder = ["generic", "claude", "chatgpt", "claude-code"]

    public static func load(userDirectory: URL? = VoxaraPaths.supportDirectory.appendingPathComponent("PromptProfiles")) throws -> ProfileStore {
        guard let bundled = Bundle.module.url(forResource: "PromptProfiles", withExtension: nil) else { throw ProfileError.missingBundle }
        var profiles: [String: PromptProfile] = [:]
        let decoder = JSONDecoder()
        func read(from directory: URL) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" && file.lastPathComponent != "presets.json" {
                if let data = try? Data(contentsOf: file), let profile = try? decoder.decode(PromptProfile.self, from: data) {
                    profiles[profile.id] = profile
                }
            }
        }
        read(from: bundled)
        if let userDirectory { read(from: userDirectory) }

        let presetData = try Data(contentsOf: bundled.appendingPathComponent("presets.json"))
        let file = try decoder.decode(PresetFile.self, from: presetData)
        var presets: [PromptPreset: PresetConfig] = [:]
        for (key, value) in file.presets { if let preset = PromptPreset(rawValue: key) { presets[preset] = value } }
        return ProfileStore(profiles: profiles, presets: presets)
    }

    public func profile(_ id: String) -> PromptProfile {
        profiles[id] ?? profiles["generic"]!
    }

    public var ordered: [PromptProfile] {
        Self.profileOrder.compactMap { profiles[$0] } + profiles.values.filter { !Self.profileOrder.contains($0.id) }.sorted { $0.name < $1.name }
    }

    public func preset(_ preset: PromptPreset) -> PresetConfig {
        presets[preset] ?? PresetConfig(sections: ["requirements"], signals: false, compact: true)
    }
}
