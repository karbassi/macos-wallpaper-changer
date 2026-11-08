// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallpaperChanger",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WallpaperChanger",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
