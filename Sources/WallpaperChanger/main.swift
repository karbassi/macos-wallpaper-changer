import AppKit

// A menu bar app in plain AppKit: LSUIElement in Info.plist keeps it out of the Dock.
// Top-level code runs on the main thread; tell the compiler so.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
