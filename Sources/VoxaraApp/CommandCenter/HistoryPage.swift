import SwiftUI
import VoxaraCore

struct HistoryRow: View {
    let entry: DictationRecord

    var body: some View {
        HStack(alignment: .top, spacing: VX.Space.md) {
            Text(entry.mode == .prompt ? "◆" : "●").font(.system(size: 10)).foregroundStyle(VX.Palette.accent).padding(.top, 4)
            VStack(alignment: .leading, spacing: VX.Space.xs) {
                HStack(spacing: VX.Space.sm) {
                    Text(HistoryFormat.label(entry)).font(VX.Font.eyebrow).tracking(0.7).foregroundStyle(VX.Palette.textTertiary)
                    if !entry.inserted { Chip(text: "NOT INSERTED", tint: VX.Palette.warning) }
                }
                Text(entry.finalText).font(VX.Font.body).foregroundStyle(VX.Palette.textPrimary).lineLimit(2)
            }
            Spacer(minLength: VX.Space.md)
            Text(entry.date, style: .time).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
        }
    }
}

enum HistoryFormat {
    /// "PROMPT · CLAUDE CODE" or "DICTATION · ENGLISH"
    static func label(_ entry: DictationRecord) -> String {
        if entry.mode == .prompt {
            let profile = ProfileNames.display(entry.promptProfile ?? "generic")
            return "PROMPT · \(profile)".uppercased()
        }
        return "DICTATION · \(entry.detectedLanguage.displayName)".uppercased()
    }
}

enum ProfileNames {
    static func display(_ id: String) -> String {
        switch id {
        case "claude-code": "Claude Code"
        case "chatgpt": "ChatGPT"
        case "claude": "Claude"
        case "generic": "Generic"
        default: id.capitalized
        }
    }
}

struct HistoryPage: View {
    let model: AppModel
    @LocalState private var query = ""
    @LocalState private var filter: Filter = .all
    @LocalState private var selection: DictationRecord.ID?
    @LocalState private var confirmClear = false

    enum Filter: String, CaseIterable { case all = "All", dictation = "Dictation", prompt = "Prompt" }

    private var mode: HotkeyAction? {
        switch filter { case .all: nil; case .dictation: .dictation; case .prompt: .prompt }
    }

    private var results: [DictationRecord] { model.history.search(query, mode: mode) }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 340)
            Rectangle().fill(VX.Palette.border).frame(width: 1)
            detail.frame(maxWidth: .infinity)
        }
        .background(VX.Palette.background)
        .alert("Clear all history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { model.history.clear(); selection = nil }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes every saved dictation and prompt from this Mac.") }
    }

    private var list: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: VX.Space.md) {
                HStack {
                    Text("History").font(VX.Font.title).foregroundStyle(VX.Palette.textPrimary)
                    Spacer()
                    if !model.history.entries.isEmpty {
                        Button("Clear") { confirmClear = true }.buttonStyle(.plain)
                            .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                    }
                }
                TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                Picker("", selection: $filter) { ForEach(Filter.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
            }
            .padding(VX.Space.lg)
            Divider().overlay(VX.Palette.border)

            if results.isEmpty {
                EmptyState(
                    title: model.history.entries.isEmpty ? "No history yet" : "No matches",
                    message: model.settings.saveHistory ? "Text only — audio is never saved." : "History saving is turned off in Settings."
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { entry in
                            Button { selection = entry.id } label: {
                                HistoryRow(entry: entry)
                                    .padding(.horizontal, VX.Space.lg).padding(.vertical, VX.Space.md)
                                    .background(selection == entry.id ? VX.Palette.surfaceRaised : .clear)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(VX.Palette.border)
                        }
                    }
                }
            }
        }
        .background(VX.Palette.sidebar.opacity(0.5))
    }

    @ViewBuilder private var detail: some View {
        if let id = selection ?? results.first?.id, let entry = model.history.entries.first(where: { $0.id == id }) {
            HistoryDetail(model: model, entry: entry, onDelete: { model.history.delete(entry.id); selection = nil })
                .id(entry.id)
        } else {
            EmptyState(title: "Select an entry", message: "See the original speech next to what Voxara produced.")
        }
    }
}

struct HistoryDetail: View {
    let model: AppModel
    let entry: DictationRecord
    let onDelete: () -> Void
    @LocalState private var copied: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                header
                block(title: entry.mode == .prompt ? "Voice transcript" : "Original", text: entry.rawTranscript, copyKey: "raw")
                Rectangle().fill(VX.Palette.border).frame(height: 1)
                block(title: entry.mode == .prompt ? "Compiled prompt" : "Final", text: entry.finalText, copyKey: "final", emphasized: true)
                if let notice = entry.notice {
                    Text(notice).font(VX.Font.caption).foregroundStyle(VX.Palette.warning)
                }
                timings
            }
            .padding(VX.Space.xl)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: VX.Space.xs) {
                Text(HistoryFormat.label(entry)).font(VX.Font.eyebrow).tracking(0.9).foregroundStyle(VX.Palette.accent)
                Text("\(entry.targetApp ?? "Unknown app") · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
            }
            Spacer()
            Button("Copy") { copy(entry.finalText, key: "final") }.buttonStyle(QuietButtonStyle())
            Button("Insert again") { reinsert() }.buttonStyle(QuietButtonStyle())
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(QuietButtonStyle())
        }
    }

    private func block(title: String, text: String, copyKey: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: VX.Space.sm) {
            HStack {
                Eyebrow(title)
                Spacer()
                Button(copied == copyKey ? "Copied" : "Copy") { copy(text, key: copyKey) }
                    .buttonStyle(.plain).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
            }
            Text(text)
                .font(entry.mode == .prompt && emphasized ? VX.Font.mono : VX.Font.body)
                .foregroundStyle(emphasized ? VX.Palette.textPrimary : VX.Palette.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VX.Space.md + 2)
                .background(VX.Palette.surface, in: RoundedRectangle(cornerRadius: VX.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: VX.Radius.md).strokeBorder(VX.Palette.border))
        }
    }

    private var timings: some View {
        let t = entry.timings
        return HStack(spacing: VX.Space.xl) {
            MetricView(label: "Spoken", value: OverviewPage.seconds(t.audioDuration))
            MetricView(label: "Speech-to-text", value: OverviewPage.seconds(t.stt))
            MetricView(label: entry.mode == .prompt ? "Prompt build" : "Cleanup", value: OverviewPage.seconds(t.processing),
                       detail: entry.processor)
            MetricView(label: "Total", value: OverviewPage.seconds(t.perceived), detail: "release → text")
        }
    }

    private func copy(_ text: String, key: String) {
        NSPasteboard.general.writePlainText(text)
        copied = key
    }

    /// Puts the text back into the app it came from (activating it), via the normal insertion path.
    private func reinsert() {
        guard let bundleID = entry.targetBundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            copy(entry.finalText, key: "final")
            return
        }
        model.reinsert(entry.finalText, into: app)
    }
}
