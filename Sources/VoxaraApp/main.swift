import AppKit

let app = NSApplication.shared

// `Voxara --snapshot <dir>`: render the UI to PNG files for review, then exit.
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index + 1 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    MainActor.assumeIsolated { SnapshotRenderer.run(into: directory) }
    exit(0)
}

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
