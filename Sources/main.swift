import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    // Accessory policy: runs in the menu bar without cluttering the Dock
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
