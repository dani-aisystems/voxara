import AppKit
import VoxaraCore

@MainActor
final class StatusMenuController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pipeline: DictationPipeline
    private let statusLine = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private let warningLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let modelLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let copyLastItem = NSMenuItem(title: "Copy Last Result", action: #selector(copyLast), keyEquivalent: "")

    init(pipeline: DictationPipeline) {
        self.pipeline = pipeline
        super.init()
        setIcon("mic")
        let menu = NSMenu()
        menu.autoenablesItems = false
        statusLine.isEnabled = false
        warningLine.isHidden = true
        modelLine.isHidden = true
        modelLine.isEnabled = false
        warningLine.action = #selector(openAccessibility)
        warningLine.target = self
        copyLastItem.target = self
        menu.addItem(statusLine)
        menu.addItem(warningLine)
        menu.addItem(modelLine)
        menu.addItem(.separator())
        menu.addItem(copyLastItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Voxara", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
    }

    func update(state: PipelineState) {
        switch state {
        case .idle:
            statusLine.title = "Ready"
            setIcon("mic")
        case .listening(let action, _):
            statusLine.title = action == .prompt ? "Listening (Prompt)…" : "Listening…"
            setIcon("mic.fill")
        case .transcribing:
            statusLine.title = "Transcribing…"
            setIcon("waveform")
        case .processing(_, let stage):
            statusLine.title = stage == .buildingPrompt ? "Building prompt…" : "Refining…"
            setIcon("waveform")
        case .done:
            statusLine.title = "Ready"
            setIcon("mic")
        case .failed(let message, _):
            statusLine.title = message
            setIcon("exclamationmark.triangle")
        }
        copyLastItem.isEnabled = pipeline.lastResult != nil
    }

    func setPermissionWarning(_ text: String?) {
        warningLine.title = text.map { "⚠︎ \($0)" } ?? ""
        warningLine.isHidden = text == nil
    }

    func setModelStatus(_ text: String?) {
        modelLine.title = text ?? ""
        modelLine.isHidden = text == nil
    }

    private func setIcon(_ symbol: String) {
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Voxara")
    }

    @objc private func copyLast() {
        guard let text = pipeline.lastResult else { return }
        NSPasteboard.general.writePlainText(text)
    }

    @objc private func openAccessibility() {
        Permissions.openAccessibilitySettings()
    }
}
