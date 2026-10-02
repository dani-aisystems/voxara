import SwiftUI
import VoxaraCore

struct VocabularyPage: View {
    let model: AppModel
    @LocalState private var newTerm = ""
    @LocalState private var testInput = "Провери дешбод компонента и виж дали епи заявките са много."
    @LocalState private var testOutput = ""

    var body: some View {
        Page(title: "Vocabulary", subtitle: "Terms Voxara should write exactly your way. Aliases are mis-transcriptions it should correct.") {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                add
                list
                test
            }
        }
    }

    private var add: some View {
        HStack {
            TextField("Add a term, e.g. Vercel", text: $newTerm).textFieldStyle(.roundedBorder).onSubmit(addTerm)
            Button("Add", action: addTerm).buttonStyle(AccentButtonStyle()).disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
            Button("Reset to defaults") { model.vocabulary.resetToDefaults(); model.vocabularyChanged() }.buttonStyle(QuietButtonStyle())
        }
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        model.vocabulary.upsert(VocabularyEntry(term: term))
        model.vocabularyChanged()
        newTerm = ""
    }

    private var list: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                ForEach(model.vocabulary.entries) { entry in
                    EntryRow(entry: entry) { updated in
                        model.vocabulary.upsert(updated)
                        model.vocabularyChanged()
                    } onDelete: {
                        model.vocabulary.delete(entry.id)
                        model.vocabularyChanged()
                    }
                    Divider().overlay(VX.Palette.border)
                }
            }
        }
    }

    private var test: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Test")
            Panel {
                VStack(alignment: .leading, spacing: VX.Space.md) {
                    TextField("Text as recognised", text: $testInput).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Apply vocabulary") {
                            Task {
                                let repairer = TermRepairer(entries: model.vocabulary.entries)
                                testOutput = await repairer.repair(testInput).text
                            }
                        }.buttonStyle(QuietButtonStyle())
                        Spacer()
                    }
                    if !testOutput.isEmpty { Text(testOutput).font(VX.Font.body).foregroundStyle(VX.Palette.textPrimary).textSelection(.enabled) }
                    Text("Genuine Bulgarian words are never replaced: a sound-alike match is only made when the macOS Bulgarian dictionary does not know the word.")
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                }
            }
        }
    }
}

private struct EntryRow: View {
    let entry: VocabularyEntry
    let onChange: (VocabularyEntry) -> Void
    let onDelete: () -> Void
    @LocalState private var aliases: String

    init(entry: VocabularyEntry, onChange: @escaping (VocabularyEntry) -> Void, onDelete: @escaping () -> Void) {
        self.entry = entry
        self.onChange = onChange
        self.onDelete = onDelete
        _aliases = State(initialValue: entry.aliases.joined(separator: ", "))
    }

    var body: some View {
        HStack(spacing: VX.Space.md) {
            Toggle("", isOn: Binding(get: { entry.enabled }, set: { var e = entry; e.enabled = $0; onChange(e) }))
                .toggleStyle(.switch).labelsHidden().controlSize(.small)
            Text(entry.term).font(VX.Font.bodyEmphasis).foregroundStyle(VX.Palette.textPrimary).frame(width: 130, alignment: .leading)
            TextField("Aliases, comma separated", text: $aliases)
                .textFieldStyle(.plain).font(VX.Font.body).foregroundStyle(VX.Palette.textSecondary)
                .onSubmit(commit)
            Button { var e = entry; e.matchPhonetically.toggle(); onChange(e) } label: {
                Text("By sound").font(VX.Font.caption)
                    .foregroundStyle(entry.matchPhonetically ? VX.Palette.accent : VX.Palette.textTertiary)
            }.buttonStyle(.plain).help("Also restore sound-alike Cyrillic spellings of this term in Bulgarian speech")
            Button(action: onDelete) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(VX.Palette.textTertiary)
        }
        .padding(.horizontal, VX.Space.lg).padding(.vertical, VX.Space.sm + 2)
        .onChange(of: aliases) { _, _ in }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let list = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard list != entry.aliases else { return }
        var e = entry
        e.aliases = list
        onChange(e)
    }
}
