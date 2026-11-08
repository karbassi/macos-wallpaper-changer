import AppKit
import Foundation
import ServiceManagement

/// App state and actions. The menu is rebuilt from this each time it opens, so nothing
/// needs to observe it; only icon visibility is pushed out, via `onShowIconChange`.
@MainActor
final class AppModel {
    static let shared = AppModel()

    static let intervals: [(label: String, seconds: TimeInterval)] = [
        ("15 Minutes", 15 * 60),
        ("30 Minutes", 30 * 60),
        ("Hour", 60 * 60),
        ("3 Hours", 3 * 60 * 60),
        ("Day", 24 * 60 * 60),
        ("Never", 0),
    ]

    private enum Key {
        static let interval = "interval"
        static let showIcon = "showMenuBarIcon"
        static let current = "currentWallpaper"
        static let unsplashKey = "unsplashClientID"
        static let offeredCacheAccess = "offeredCacheAccess"
    }

    private let defaults = UserDefaults.standard
    /// One-shot timer for the next due change; nothing polls in between.
    private var timer: Timer?
    private var started = false
    private var retryAfter = Date.distantPast

    private(set) var current: Wallpaper?
    private(set) var isChanging = false
    private(set) var lastError: String?
    private(set) var hasCacheAccess = CacheCleaner.hasAccess
    private(set) var lastCleanup: String?
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    /// Called when the menu bar icon should be added or removed.
    var onShowIconChange: (() -> Void)?

    var interval: TimeInterval {
        didSet {
            guard interval != oldValue else { return }
            defaults.set(interval, forKey: Key.interval)
            changeIfDue()
        }
    }

    var showIcon: Bool {
        didSet {
            guard showIcon != oldValue else { return }
            defaults.set(showIcon, forKey: Key.showIcon)
            onShowIconChange?()
        }
    }

    var unsplashKey: String? {
        let key = defaults.string(forKey: Key.unsplashKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return key?.isEmpty == false ? key : nil
    }

    private init() {
        defaults.register(defaults: [Key.interval: 3600.0, Key.showIcon: true])
        interval = defaults.double(forKey: Key.interval)
        showIcon = defaults.bool(forKey: Key.showIcon)
        if let data = defaults.data(forKey: Key.current) {
            current = try? JSONDecoder().decode(Wallpaper.self, from: data)
        }
    }

    // MARK: Scheduling

    func start() {
        guard !started else { return }
        started = true
        logger.info("Starting scheduler (interval \(self.interval, privacy: .public)s)")
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            // Give the network a moment to come back after sleep.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                AppModel.shared.changeIfDue()
            }
        }
        changeIfDue()
        Task { await cleanUp() }
    }

    /// When the next automatic change is due, or nil when changes are off.
    private var nextDue: Date? {
        guard interval > 0 else { return nil }
        let due = (current?.setAt ?? .distantPast).addingTimeInterval(interval)
        return max(due, retryAfter)
    }

    /// Change the wallpaper if it's due; otherwise arm a single timer for when it will be.
    func changeIfDue() {
        guard started, !isChanging else { return }
        guard let due = nextDue else {
            timer?.invalidate()
            timer = nil
            return
        }
        if due <= Date() {
            next()
        } else {
            schedule(at: due)
        }
    }

    private func schedule(at date: Date) {
        timer?.invalidate()
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            Task { @MainActor in AppModel.shared.changeIfDue() }
        }
        // Let macOS coalesce this wakeup with others; a minute either way doesn't matter.
        timer.tolerance = min(60, interval / 10)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func next() {
        guard !isChanging else { return }
        isChanging = true
        Task {
            defer {
                isChanging = false
                changeIfDue() // arm the timer for the next change (or the retry)
            }
            do {
                let wallpaper = try await WallpaperService.fetch(unsplashKey: unsplashKey)
                try WallpaperService.apply(wallpaper.file)
                current = wallpaper
                defaults.set(try? JSONEncoder().encode(wallpaper), forKey: Key.current)
                lastError = nil
            } catch {
                logger.error("Change failed: \(error.localizedDescription, privacy: .public)")
                lastError = error.localizedDescription
                retryAfter = Date().addingTimeInterval(5 * 60) // don't hammer the API on repeated failures
                return
            }
            await cleanUp()
            offerCacheAccessOnce()
        }
    }

    // MARK: Cache

    /// Retire old downloads and delete this app's cached copies from macOS's wallpaper caches.
    func cleanUp() async {
        let keep = current?.file
        let bookmarks = CacheCleaner.bookmarks()
        let result = await Task.detached { CacheCleaner.run(keeping: keep, bookmarks: bookmarks) }.value

        CacheCleaner.store(result.refreshedBookmarks)
        if !result.lostAccess.isEmpty {
            logger.error("Lost access to cache folders: \(result.lostAccess.map(\.rawValue).sorted().joined(separator: ", "), privacy: .public)")
            CacheCleaner.forgetAccess(result.lostAccess)
        }
        hasCacheAccess = CacheCleaner.hasAccess
        if result.files > 0 || result.choicesRemoved > 0 {
            let size = ByteCountFormatter.string(fromByteCount: result.bytes, countStyle: .file)
            lastCleanup = "Removed \(size) at \(Date().formatted(date: .omitted, time: .shortened))"
        }
    }

    func allowCacheCleanup() {
        if CacheCleaner.requestAccess() {
            hasCacheAccess = true
            Task { await cleanUp() }
        }
        hasCacheAccess = CacheCleaner.hasAccess
    }

    /// After the first change, explain the cache once and offer to allow cleanup.
    private func offerCacheAccessOnce() {
        guard !hasCacheAccess, !defaults.bool(forKey: Key.offeredCacheAccess) else { return }
        defaults.set(true, forKey: Key.offeredCacheAccess)

        let alert = NSAlert()
        alert.messageText = "Keep macOS's wallpaper cache from growing?"
        alert.informativeText = """
        macOS keeps copies of every wallpaper ever set, about 10–30 MB each, plus a list entry for each \
        one, and never removes them. Once that list gets long, wallpapers stop changing. \
        Wallpaper Changer can remove what it creates.

        macOS will show an Open dialog for each of two folders; just click Allow Access.
        """
        alert.addButton(withTitle: "Allow…")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            allowCacheCleanup()
        }
    }

    // MARK: Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = "Open at Login: \(error.localizedDescription)"
        }
    }

    func promptForUnsplashKey() {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = unsplashKey ?? ""
        field.placeholderString = "Unsplash access key"

        let alert = NSAlert()
        alert.messageText = "Unsplash Access Key"
        alert.informativeText = "Used for Unsplash photos. Without it, only Google Earth images are shown. Get one at unsplash.com/developers."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        defaults.set(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.unsplashKey)
        lastError = nil
        retryAfter = .distantPast
    }

    func confirmHideIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide the menu bar icon?"
        alert.informativeText = """
        Wallpaper Changer keeps running and changing your wallpaper.

        To show the icon again, open Wallpaper Changer from Applications or Spotlight. \
        You can also open wallpaperchanger://show, or wallpaperchanger://next to change the wallpaper.
        """
        alert.addButton(withTitle: "Hide Icon")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            showIcon = false
        }
    }
}
