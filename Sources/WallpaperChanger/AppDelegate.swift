import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel.shared
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onShowIconChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
        model.start()
    }

    /// Opening the app again (Finder, Spotlight, `open -a`) brings back a hidden menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        model.showIcon = true
        return false
    }

    /// wallpaperchanger://next, ://show, ://hide
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host() {
            case "next": model.next()
            case "show": model.showIcon = true
            case "hide": model.showIcon = false
            default: logger.error("Unknown URL: \(url.absoluteString, privacy: .public)")
            }
        }
    }

    // MARK: Status item

    /// Hidden means no status item at all, not an invisible one.
    private func updateStatusItem() {
        if model.showIcon {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Wallpaper Changer")
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// Rebuilt from the model every time it opens, so there's no state to keep in sync.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let wallpaper = model.current {
            if let link = wallpaper.link {
                menu.addItem(ActionItem(wallpaper.credit) { NSWorkspace.shared.open(link) })
            } else {
                menu.addItem(label(wallpaper.credit))
            }
            menu.addItem(label("Changed at \(wallpaper.setAt.formatted(date: .omitted, time: .shortened))"))
        }
        if let error = model.lastError {
            menu.addItem(label("⚠️ \(error)"))
        }

        let next = ActionItem(model.isChanging ? "Changing…" : "Next Wallpaper", key: "n") { [model] in model.next() }
        next.isEnabled = !model.isChanging
        menu.addItem(next)

        let intervals = NSMenu()
        for option in AppModel.intervals {
            let item = ActionItem(option.label) { [model] in model.interval = option.seconds }
            item.state = model.interval == option.seconds ? .on : .off
            intervals.addItem(item)
        }
        let every = NSMenuItem(title: "Change Every", action: nil, keyEquivalent: "")
        every.submenu = intervals
        menu.addItem(every)

        menu.addItem(.separator())

        if model.hasCacheAccess {
            menu.addItem(ActionItem("Clean Up Cached Copies Now") { [model] in Task { await model.cleanUp() } })
            if let lastCleanup = model.lastCleanup {
                menu.addItem(label(lastCleanup))
            }
        } else {
            menu.addItem(ActionItem("Allow Cache Cleanup…") { [model] in model.allowCacheCleanup() })
        }

        menu.addItem(.separator())

        let login = ActionItem("Open at Login") { [model] in model.setLaunchAtLogin(!model.launchAtLogin) }
        login.state = model.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(ActionItem("Unsplash Access Key…") { [model] in model.promptForUnsplashKey() })
        menu.addItem(ActionItem("Hide Menu Bar Icon…") { [model] in model.confirmHideIcon() })

        menu.addItem(.separator())

        menu.addItem(ActionItem("Quit Wallpaper Changer", key: "q") { NSApp.terminate(nil) })
    }

    private func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// A menu item that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
