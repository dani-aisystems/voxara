import SwiftUI
import VoxaraCore

struct PromptPage: View {
    let model: AppModel
    @LocalState private var input = ""
    @LocalState private var output = ""
    @LocalState private var notice: String?
    @LocalState private var working = false
    @LocalState private var elapsed: TimeInterval?
    @LocalState private var expandedProfile: String?

    var body: some View {
        Page(title: "Prompt Mode", subtitle: "Turn rambling speech into a prompt an AI can act on. Preserve intent, improve structure, never invent requirements.") {
            VStack(alignment: .leading, spacing: VX.Space.xl) {
                profiles
                presets
                options
                tryIt
            }
        }
    }

    // MARK: Profiles

    private var profiles: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Default destination")
            Panel {
                VStack(alignment: .leading, spacing: VX.Space.md) {
                    ForEach(model.profiles.ordered) { profile in
                        VStack(alignment: .leading, spacing: VX.Space.sm) {
                            ChoiceRow(title: profile.name, detail: Self.tagline(profile.id), selected: model.settings.promptProfile == profile.id) {
                                model.settings.promptProfile = profile.id
                            }
                            if expandedProfile == profile.id {
                                Text(profile.philosophy).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                                    .padding(.leading, VX.Space.xl).fixedSize(horizontal: false, vertical: true)
                            }
                            Button(expandedProfile == profile.id ? "Hide approach" : "How it writes") {
                                expandedProfile = expandedProfile == profile.id ? nil : profile.id
                            }
                            .buttonStyle(.plain).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary).padding(.leading, VX.Space.xl)
                        }
                    }
                    Text("Profiles are editable JSON files in ~/Library/Application Support/Voxara/PromptProfiles.")
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                    Button("Open profiles folder") { openProfilesFolder() }.buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    static func tagline(_ id: String) -> String {
        switch id {
        case "generic": "A clear, self-contained instruction for any assistant."
        case "claude": "Explicit instructions with distinct, tagged sections."
        case "chatgpt": "Outcome first, concise sections."
        case "claude-code": "For autonomous repository work: inspect first, scoped changes, verification."
        default: ""
        }
    }

    private func openProfilesFolder() {
        let dir = VoxaraPaths.supportDirectory.appendingPathComponent("PromptProfiles")
        try? VoxaraPaths.ensure(dir)
        if let bundled = Bundle.module_profilesURL {
            for file in (try? FileManager.default.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "json" && file.lastPathComponent != "presets.json" {
                let target = dir.appendingPathComponent(file.lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) { try? FileManager.default.copyItem(at: file, to: target) }
            }
        }
        NSWorkspace.shared.open(dir)
    }

    // MARK: Presets & options

    private var presets: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Depth")
            Panel {
                VStack(alignment: .leading, spacing: VX.Space.md) {
                    ForEach(PromptPreset.allCases, id: \.self) { preset in
                        ChoiceRow(title: preset.displayName, detail: preset.explanation, selected: model.settings.promptPreset == preset) {
                            model.settings.promptPreset = preset
                        }
                    }
                }
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Behaviour")
            Panel {
                VStack(alignment: .leading, spacing: VX.Space.md) {
                    Toggle(isOn: Binding(get: { model.settings.contextAware }, set: { model.settings.contextAware = $0 })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggest a profile from the active app").font(VX.Font.bodyEmphasis)
                            Text("Terminal and code editors → Claude Code, ChatGPT → ChatGPT, Claude → Claude. Only the profile changes, never what you said. Override per app under Applications.")
                                .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                        }
                    }.toggleStyle(.switch)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Write the prompt in").font(VX.Font.bodyEmphasis)
                            Text("Bulgarian speech can produce an English prompt; technical terms are kept as spoken.")
                                .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                        }
                        Spacer()
                        Picker("", selection: Binding(get: { model.settings.promptOutputLanguage }, set: { model.settings.promptOutputLanguage = $0 })) {
                            ForEach(PromptOutputLanguage.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }.labelsHidden().frame(width: 160)
                    }
                }
            }
        }
    }

    // MARK: Try it

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: VX.Space.md) {
            Eyebrow("Try it")
            Panel {
                VStack(alignment: .leading, spacing: VX.Space.md) {
                    Text("Type or paste what you might say. Nothing is inserted anywhere.")
                        .font(VX.Font.caption).foregroundStyle(VX.Palette.textSecondary)
                    TextEditor(text: $input)
                        .font(VX.Font.body).scrollContentBackground(.hidden)
                        .frame(height: 96).padding(VX.Space.sm)
                        .background(VX.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: VX.Radius.md))
                    HStack {
                        Button(working ? "Building…" : "Build prompt") { build() }
                            .buttonStyle(AccentButtonStyle()).disabled(working || input.trimmingCharacters(in: .whitespaces).isEmpty)
                        Text("\(ProfileNames.display(model.settings.promptProfile)) · \(model.settings.promptPreset.displayName)")
                            .font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary)
                        if let elapsed { Text(OverviewPage.seconds(elapsed)).font(VX.Font.caption).foregroundStyle(VX.Palette.textTertiary) }
                        Spacer()
                    }
                    if !output.isEmpty {
                        Text(output).font(VX.Font.mono).textSelection(.enabled)
                            .foregroundStyle(VX.Palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(VX.Space.md)
                            .background(VX.Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: VX.Radius.md))
                        HStack {
                            if let notice { Text(notice).font(VX.Font.caption).foregroundStyle(VX.Palette.warning) }
                            Spacer()
                            Button("Copy") { NSPasteboard.general.writePlainText(output) }.buttonStyle(QuietButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func build() {
        working = true
        notice = nil
        let start = Date()
        let context = ResolvedContext(mode: .prompt, promptProfile: model.settings.promptProfile,
                                      promptPreset: model.settings.promptPreset, cleanup: model.settings.cleanup, source: "Try it")
        Task {
            let result = await model.pipeline.preview(input, action: .prompt, context: context)
            output = result.text
            notice = result.notice
            elapsed = Date().timeIntervalSince(start)
            working = false
        }
    }
}

extension Bundle {
    /// Location of the bundled prompt profiles (resource bundle copied into the app).
    static var module_profilesURL: URL? {
        for candidate in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let url = candidate?.appendingPathComponent("Voxara_VoxaraCore.bundle/PromptProfiles"),
               FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
