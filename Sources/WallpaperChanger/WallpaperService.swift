import AppKit
import Foundation
import OSLog
import UniformTypeIdentifiers

let logger = Logger(subsystem: "com.karbassi.WallpaperChanger", category: "wallpaper")

/// The wallpaper currently on screen, persisted across launches.
struct Wallpaper: Codable, Equatable {
    var file: URL
    var credit: String
    var link: URL?
    var setAt: Date
}

struct Source {
    enum Kind {
        case unsplash([URLQueryItem])
        case direct(URL)
    }

    let name: String
    let kind: Kind

    var needsUnsplashKey: Bool {
        if case .unsplash = kind { return true }
        return false
    }

    static let all: [Source] = [
        .init(name: "Wallpapers for macOS", kind: .unsplash([.init(name: "collections", value: "7282015")])),
        .init(name: "Unsplash Editorial", kind: .unsplash([.init(name: "collections", value: "317099")])),
        .init(name: "Patterns", kind: .unsplash([.init(name: "collections", value: "8961198")])),
        .init(name: "Wallpapers", kind: .unsplash([.init(name: "query", value: "wallpapers")])),
        .init(name: "Architecture", kind: .unsplash([.init(name: "query", value: "architecture")])),
        .init(name: "Wallpapers topic", kind: .unsplash([.init(name: "topics", value: "wallpapers")])),
        .init(name: "NASA", kind: .unsplash([.init(name: "username", value: "nasa")])),
        .init(name: "Google Earth", kind: .direct(URL(string: "https://random-google-earth.vercel.app/")!)),
    ]
}

struct WallpaperError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum WallpaperService {
    static let filePrefix = "random-wallpaper."

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        return URLSession(configuration: config)
    }()

    // MARK: Fetch

    /// Pick a random source, download its image, and return it (not yet set).
    /// Without an Unsplash key, only non-Unsplash sources are used.
    static func fetch(unsplashKey: String?) async throws -> Wallpaper {
        let candidates = Source.all.filter { unsplashKey != nil || !$0.needsUnsplashKey }
        let source = candidates.randomElement()!
        logger.info("Fetching from \(source.name, privacy: .public)")

        switch source.kind {
        case .direct(let url):
            let file = try await download(url)
            return Wallpaper(file: file, credit: source.name, link: nil, setAt: Date())

        case .unsplash(let extra):
            let key = unsplashKey!
            var api = URLComponents(string: "https://api.unsplash.com/photos/random")!
            api.queryItems = [
                .init(name: "content_filter", value: "high"),
                .init(name: "orientation", value: "landscape"),
            ] + extra
            let json = try await unsplashJSON(api.url!, key: key)

            guard
                let urls = json["urls"] as? [String: Any],
                let raw = urls["raw"] as? String,
                var image = URLComponents(string: raw)
            else { throw WallpaperError("Unsplash response had no image URL") }
            image.queryItems = (image.queryItems ?? []) + [
                .init(name: "w", value: "2560"),
                .init(name: "h", value: "1600"),
                .init(name: "fit", value: "crop"),
            ]

            let file = try await download(image.url!)

            let links = json["links"] as? [String: Any]
            let user = json["user"] as? [String: Any]
            let name = user?["name"] as? String ?? "Unknown"
            var link = (links?["html"] as? String).flatMap(URLComponents.init(string:))
            link?.queryItems = [
                .init(name: "utm_source", value: "wallpaper_changer"),
                .init(name: "utm_medium", value: "referral"),
            ]

            // Unsplash API guidelines: report the download.
            if let tracking = (links?["download_location"] as? String).flatMap(URL.init(string:)) {
                Task.detached { _ = try? await unsplashJSON(tracking, key: key) }
            }

            return Wallpaper(file: file, credit: "Photo by \(name) on Unsplash", link: link?.url, setAt: Date())
        }
    }

    private static func unsplashJSON(_ url: URL, key: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Client-ID \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("v1", forHTTPHeaderField: "Accept-Version")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw WallpaperError("Unsplash rejected the access key") }
        guard status == 200 else { throw WallpaperError("Unsplash returned HTTP \(status)") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WallpaperError("Unsplash returned unexpected data")
        }
        return json
    }

    /// Download into the app's own folder as random-wallpaper.XXXXX.<ext>. Not the temp dir:
    /// macOS purges it on its own schedule, which could pull an image out from under a Space.
    private static func download(_ url: URL) async throws -> URL {
        let (tempFile, response) = try await session.download(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw WallpaperError("Image download returned HTTP \(status)") }
        guard let mime = response.mimeType, mime.hasPrefix("image/") else {
            throw WallpaperError("Download was not an image (\(response.mimeType ?? "unknown type"))")
        }
        let ext = UTType(mimeType: mime)?.preferredFilenameExtension ?? "jpg"
        let name = "\(filePrefix)\(UUID().uuidString.prefix(5)).\(ext)"
        try FileManager.default.createDirectory(at: CacheCleaner.downloadsDir, withIntermediateDirectories: true)
        let destination = CacheCleaner.downloadsDir.appending(path: name)
        try FileManager.default.moveItem(at: tempFile, to: destination)
        return destination
    }

    // MARK: Apply

    @MainActor
    static func apply(_ file: URL) throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw WallpaperError("No screens found") }
        for screen in screens {
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: options)
        }
    }
}
