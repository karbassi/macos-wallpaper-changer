import AppKit
import CryptoKit
import Foundation

// macOS Sonoma+ keeps state for every wallpaper ever set and never cleans it up:
//
// - WallpaperAgent renders each image to an uncompressed BMP, one per display size, named
//   "<sha256 of the image's path>-<w>-<h>-0-<id>.bmp".
// - The image extension keeps a JPEG copy of each image under a random name, and a
//   bookmark entry for it in its preferences (ChoiceRequests.ImageFiles). Past roughly
//   4 MB (~3,000 entries) that list makes the extension time out, and wallpapers stop
//   changing at all.
//
// These live in other apps' containers, which macOS protects. Rather than Full Disk Access,
// the user grants each folder once through an Open dialog (user intent), saved as a
// security-scoped bookmark — the approach Aerial uses.
//
// Only this app's state is removed, and never for an image any Space or display still shows.

enum CacheFolder: String, CaseIterable {
    case agent
    case imageExtension

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .agent:
            return home.appending(path: "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.image")
        case .imageExtension:
            // Library, not just Caches: the choice list lives in Library/Preferences.
            return home.appending(path: "Library/Containers/com.apple.wallpaper.extension.image/Data/Library")
        }
    }

    var bookmarkKey: String {
        switch self {
        case .agent: "cacheBookmark.agent"
        case .imageExtension: "cacheBookmark.imageExtensionLibrary"
        }
    }

    var description: String {
        switch self {
        case .agent: "full-size copies of every wallpaper, one per display,"
        case .imageExtension: "a JPEG copy and a list entry for every wallpaper (a long list stops wallpapers from changing),"
        }
    }
}

/// A wallpaper download this app has deleted, kept long enough to find its cached copies.
struct RetiredWallpaper: Codable, Hashable {
    var pathHash: String
    var contentHash: String
    var size: Int64
    var retiredAt: Date
}

struct CleanResult: Sendable {
    var files = 0
    var bytes: Int64 = 0
    var choicesRemoved = 0
    var choicesRemaining: Int?
    /// Folders whose bookmark no longer grants access; the user must allow them again.
    var lostAccess: Set<CacheFolder> = []
    /// Bookmarks macOS asked us to refresh.
    var refreshedBookmarks: [CacheFolder: Data] = [:]
}

enum CacheCleaner {
    /// Downloads newer than this are kept (and their cached copies) so recent wallpapers,
    /// still shown in Mission Control or mid-transition, stay intact.
    static let keepFor: TimeInterval = 2 * 60 * 60
    /// Retired entries are matched for this long; WallpaperAgent writes its copies lazily.
    static let rememberFor: TimeInterval = 7 * 24 * 60 * 60

    static let choiceListKey = "ChoiceRequests.ImageFiles"

    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "WallpaperChanger")
    }
    static var downloadsDir: URL { supportDir.appending(path: "Wallpapers") }
    private static var journalURL: URL { supportDir.appending(path: "retired.json") }
    private static var wallpaperStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    // MARK: Access

    static func bookmarks() -> [CacheFolder: Data] {
        var result: [CacheFolder: Data] = [:]
        for folder in CacheFolder.allCases {
            if let data = UserDefaults.standard.data(forKey: folder.bookmarkKey) { result[folder] = data }
        }
        return result
    }

    static var hasAccess: Bool { bookmarks().count == CacheFolder.allCases.count }

    static func forgetAccess(_ folders: Set<CacheFolder>) {
        for folder in folders { UserDefaults.standard.removeObject(forKey: folder.bookmarkKey) }
    }

    static func store(_ refreshed: [CacheFolder: Data]) {
        for (folder, data) in refreshed { UserDefaults.standard.set(data, forKey: folder.bookmarkKey) }
    }

    /// Ask the user to allow each protected folder through an Open dialog. Returns true
    /// when every folder is allowed.
    @MainActor
    static func requestAccess() -> Bool {
        let missing = CacheFolder.allCases.filter { UserDefaults.standard.data(forKey: $0.bookmarkKey) == nil }
        for (index, folder) in missing.enumerated() {
            let panel = NSOpenPanel()
            panel.title = "Allow Cache Cleanup"
            panel.message = """
            Step \(index + 1) of \(missing.count): macOS keeps \(folder.description) and never removes them. \
            Click Allow Access so Wallpaper Changer can remove the ones it created.
            """
            panel.prompt = "Allow Access"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder.url

            NSApp.activate()
            guard panel.runModal() == .OK, let chosen = panel.url else { return false }

            guard chosen.resolvingSymlinksInPath().path == folder.url.resolvingSymlinksInPath().path else {
                let alert = NSAlert()
                alert.messageText = "That's a different folder"
                alert.informativeText = "Click Allow Access without choosing anything else, so the folder the dialog opened to is the one allowed:\n\n\(folder.url.path)"
                NSApp.activate()
                alert.runModal()
                return false
            }
            do {
                let data = try chosen.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(data, forKey: folder.bookmarkKey)
            } catch {
                logger.error("Bookmark failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        return true
    }

    // MARK: Clean

    /// Retire old downloads, then remove this app's leftover state from every folder the
    /// user allowed. Safe to call without access: downloads are still retired and
    /// remembered, so their copies are removed once access is granted.
    static func run(keeping current: URL?, bookmarks: [CacheFolder: Data]) -> CleanResult {
        var result = CleanResult()
        var protected = referencedWallpapers()
        if let current { protected.insert(current.standardizedFileURL.path) }

        var journal = loadJournal()
        journal.formUnion(retireDownloads(protecting: protected))
        journal = journal.filter { Date().timeIntervalSince($0.retiredAt) < rememberFor }
        saveJournal(journal)

        for folder in CacheFolder.allCases {
            guard let data = bookmarks[folder] else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else {
                result.lostAccess.insert(folder)
                continue
            }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                result.refreshedBookmarks[folder] = fresh
            }

            switch folder {
            case .agent:
                let hashes = Set(journal.map(\.pathHash))
                deleteFiles(in: url, folder: folder, into: &result) { name, _ in
                    name.count > 64 && hashes.contains(String(name.prefix(64)))
                }
            case .imageExtension:
                pruneChoiceList(library: url, protecting: protected, into: &result)
                // JPEG copies from before the list was pruned: match by size, then content.
                let sizes = Set(journal.map(\.size))
                let contentHashes = Set(journal.map(\.contentHash))
                deleteFiles(in: url.appending(path: "Caches"), folder: folder, into: &result) { _, file in
                    let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
                    return sizes.contains(Int64(size)) && (sha256(of: file).map(contentHashes.contains) ?? false)
                }
            }
        }
        logger.info("Cleaned \(result.files) cached copies (\(result.bytes) bytes), \(result.choicesRemoved) list entries; \(result.choicesRemaining.map(String.init) ?? "unknown", privacy: .public) remain")
        return result
    }

    /// Remove this app's retired entries from the image extension's choice list, along
    /// with the JPEG copy each one points to.
    private static func pruneChoiceList(library: URL, protecting protected: Set<String>, into result: inout CleanResult) {
        let domain = library.appending(path: "Preferences/com.apple.wallpaper.extension.image").path as CFString
        let key = choiceListKey as CFString
        guard let entries = CFPreferencesCopyAppValue(key, domain) as? [Data] else {
            logger.error("Can't read the wallpaper choice list")
            return
        }

        var kept: [Data] = []
        var removedCopies: [URL] = []
        for blob in entries {
            guard
                let entry = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any],
                let original = (entry["originalURL"] as? [String: Any])?["relative"] as? String,
                let originalURL = URL(string: original), originalURL.isFileURL
            else {
                kept.append(blob)
                continue
            }
            let path = originalURL.standardizedFileURL.path
            let ours = originalURL.lastPathComponent.hasPrefix(WallpaperService.filePrefix)
            // Only entries whose download is already retired (deleted) and not on screen anywhere.
            let removable = ours && !protected.contains(path) && !FileManager.default.fileExists(atPath: path)
            if removable {
                if let copy = (entry["copyURL"] as? [String: Any])?["relative"] as? String, let copyURL = URL(string: copy) {
                    removedCopies.append(copyURL)
                }
            } else {
                kept.append(blob)
            }
        }

        result.choicesRemaining = kept.count
        guard kept.count < entries.count else { return }
        CFPreferencesSetAppValue(key, kept as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            logger.error("Can't save the wallpaper choice list")
            result.choicesRemaining = entries.count
            return
        }
        result.choicesRemoved = entries.count - kept.count

        let cachesPath = library.appending(path: "Caches").standardizedFileURL.path
        for copy in removedCopies where copy.isFileURL && copy.standardizedFileURL.path.hasPrefix(cachesPath + "/") {
            let size = (try? copy.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
            if (try? FileManager.default.removeItem(at: copy)) != nil {
                result.files += 1
                result.bytes += Int64(size)
            }
        }
    }

    private static func deleteFiles(in dir: URL, folder: CacheFolder, into result: inout CleanResult, where matches: (String, URL) -> Bool) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else {
            if FileManager.default.fileExists(atPath: dir.path) { result.lostAccess.insert(folder) }
            return
        }
        for file in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  matches(file.lastPathComponent, file) else { continue }
            do {
                try FileManager.default.removeItem(at: file)
                result.files += 1
                result.bytes += Int64(values.totalFileAllocatedSize ?? 0)
            } catch {
                logger.error("Can't delete \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                result.lostAccess.insert(folder)
                return
            }
        }
    }

    /// Delete this app's downloads older than `keepFor`, except any still on screen, and
    /// return records of them.
    private static func retireDownloads(protecting protected: Set<String>) -> Set<RetiredWallpaper> {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let dirs = [downloadsDir, fm.temporaryDirectory] // the temp dir holds downloads from earlier versions
        var retired = Set<RetiredWallpaper>()
        let cutoff = Date().addingTimeInterval(-keepFor)

        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { continue }
            for file in files where file.lastPathComponent.hasPrefix(WallpaperService.filePrefix) {
                let path = file.standardizedFileURL.path
                guard
                    !protected.contains(path),
                    let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                    let modified = values.contentModificationDate, modified < cutoff,
                    let contentHash = sha256(of: file)
                else { continue }
                retired.insert(RetiredWallpaper(
                    pathHash: sha256(path),
                    contentHash: contentHash,
                    size: Int64(values.fileSize ?? 0),
                    retiredAt: Date()
                ))
                try? fm.removeItem(at: file)
            }
        }
        return retired
    }

    /// Paths of every image file any Space or display is set to, from macOS's wallpaper store.
    private static func referencedWallpapers() -> Set<String> {
        guard
            let data = try? Data(contentsOf: wallpaperStoreURL),
            let root = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return [] }

        var paths = Set<String>()
        var stack: [Any] = [root]
        while let node = stack.popLast() {
            if let dict = node as? [String: Any] {
                if let config = dict["Configuration"] as? Data, !config.isEmpty,
                   let parsed = try? PropertyListSerialization.propertyList(from: config, format: nil) as? [String: Any],
                   let relative = (parsed["url"] as? [String: Any])?["relative"] as? String,
                   let url = URL(string: relative), url.isFileURL {
                    paths.insert(url.standardizedFileURL.path)
                }
                stack.append(contentsOf: dict.values)
            } else if let array = node as? [Any] {
                stack.append(contentsOf: array)
            }
        }
        return paths
    }

    // MARK: Helpers

    private static func sha256(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func loadJournal() -> Set<RetiredWallpaper> {
        guard let data = try? Data(contentsOf: journalURL) else { return [] }
        return (try? JSONDecoder().decode(Set<RetiredWallpaper>.self, from: data)) ?? []
    }

    private static func saveJournal(_ journal: Set<RetiredWallpaper>) {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }
}
