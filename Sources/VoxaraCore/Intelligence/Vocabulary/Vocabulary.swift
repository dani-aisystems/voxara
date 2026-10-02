import Foundation
import Observation

/// A term Voxara should write in a specific form, e.g. "GitHub" rather than "гитхаб".
public struct VocabularyEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Scope: String, Codable, CaseIterable, Sendable {
        case any, english, bulgarian

        public var displayName: String {
            switch self {
            case .any: "Any language"
            case .english: "English speech"
            case .bulgarian: "Bulgarian speech"
            }
        }
    }

    public var id: UUID
    /// Preferred output, written exactly like this.
    public var term: String
    /// Known mis-transcriptions, matched as whole words (case-insensitive).
    public var aliases: [String]
    /// Also restore phonetic Cyrillic spellings of this term in Bulgarian speech.
    public var matchPhonetically: Bool
    public var scope: Scope
    public var enabled: Bool

    public init(id: UUID = UUID(), term: String, aliases: [String] = [], matchPhonetically: Bool = true,
                scope: Scope = .any, enabled: Bool = true) {
        self.id = id
        self.term = term
        self.aliases = aliases
        self.matchPhonetically = matchPhonetically
        self.scope = scope
        self.enabled = enabled
    }
}

/// The editable personal vocabulary, seeded with common technical terms on first use.
@MainActor
@Observable
public final class VocabularyStore {
    public private(set) var entries: [VocabularyEntry]
    private let fileURL: URL

    public init(fileURL: URL = VoxaraPaths.supportDirectory.appendingPathComponent("vocabulary.json")) {
        self.fileURL = fileURL
        entries = JSONFile.read([VocabularyEntry].self, from: fileURL) ?? Self.seed
    }

    public func upsert(_ entry: VocabularyEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        persist()
    }

    public func delete(_ id: VocabularyEntry.ID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func resetToDefaults() {
        entries = Self.seed
        persist()
    }

    private func persist() {
        try? JSONFile.write(entries, to: fileURL)
    }

    /// Starting vocabulary. Aliases are mis-transcriptions actually observed from Parakeet or typical
    /// Bulgarian phonetic spellings; everything else is caught by the conservative phonetic matcher.
    public nonisolated static let seed: [VocabularyEntry] = [
        VocabularyEntry(term: "Claude Code", aliases: ["cloud code", "clod code", "клод код", "клауд код"]),
        // Never matched by sound: "клауд" is ordinary Bulgarian for "cloud".
        VocabularyEntry(term: "Claude", aliases: ["клод"], matchPhonetically: false),
        VocabularyEntry(term: "ChatGPT", aliases: ["chat gpt", "chat g p t", "чат джипити", "чатджипити", "чат джи пи ти"], matchPhonetically: false),
        VocabularyEntry(term: "GitHub", aliases: ["гитхъб", "гитхаб", "бжитхаб", "git hub"]),
        VocabularyEntry(term: "pull request", aliases: ["пул реквест", "полреквест", "пулреквест"]),
        VocabularyEntry(term: "dashboard", aliases: ["дешбод", "дешборд", "дашборд"]),
        VocabularyEntry(term: "frontend", aliases: ["фронтенд", "фронт енд"]),
        VocabularyEntry(term: "backend", aliases: ["бекенд", "бек енд", "бакенд"]),
        VocabularyEntry(term: "API", aliases: ["епи", "ей пи ай"]),
        VocabularyEntry(term: "request", aliases: ["реквест", "реквестайт", "рикуест"]),
        VocabularyEntry(term: "deploy", aliases: ["деплой"]),
        VocabularyEntry(term: "Vercel", aliases: ["верцел", "върсел"]),
        VocabularyEntry(term: "Notion", aliases: ["ноушън", "ноушан"]),
        VocabularyEntry(term: "Swift", aliases: ["суифт"]),
        VocabularyEntry(term: "Python", aliases: ["пайтън", "пайтон"]),
        VocabularyEntry(term: "JavaScript", aliases: ["джаваскрипт", "джава скрипт"]),
        VocabularyEntry(term: "TypeScript", aliases: ["тайпскрипт", "тайп скрипт"]),
        VocabularyEntry(term: "React", aliases: ["реакт"]),
        VocabularyEntry(term: "Next.js", aliases: ["next js", "nextjs", "некст джей ес", "некст джс"], matchPhonetically: false),
    ]
}
