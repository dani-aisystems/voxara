import AppKit
import SwiftUI
import VoxaraCore

/// A panel that can never become key or main, so it cannot take keyboard focus from the app being dictated into.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating status pill. Created once and reused; only its alpha and content change.
@MainActor
final class OverlayController {
    private let model: AppModel
    private let panel: NonActivatingPanel
    private var hideTask: Task<Void, Never>?

    private static let size = NSSize(width: 360, height: 52)

    init(model: AppModel) {
        self.model = model
        panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        panel.alphaValue = 0
    }

    func update(state: PipelineState) {
        guard model.settings.showOverlay else { hide(after: 0); return }
        hideTask?.cancel()
        switch state {
        case .idle:
            hide(after: 0)
        case .listening, .transcribing, .processing:
            show()
        case .done(_, _, let notice):
            show()
            hide(after: notice == nil ? 0.9 : 2.5)
        case .failed(_, let recoverable):
            show()
            hide(after: recoverable == nil ? 3.5 : 6)
        }
    }

    private func show() {
        position()
        if panel.alphaValue < 1 || !panel.isVisible {
            // orderFrontRegardless keeps the frontmost app active; the panel never becomes key.
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = VX.Motion.fast
                panel.animator().alphaValue = 1
            }
        }
    }

    private func hide(after delay: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = VX.Motion.normal
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.panel.alphaValue == 0 else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    /// Bottom-centre of the screen that currently has the keyboard focus.
    private func position() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 76)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: false)
    }
}
