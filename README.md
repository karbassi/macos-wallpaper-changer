# Wallpaper Changer

A macOS menu bar app that sets a random wallpaper on a schedule: Unsplash collections and searches, NASA, or a random Google Earth view. Requires macOS 14 or later.

macOS Sonoma and later keeps its own copies of every wallpaper ever set, even after the source file is deleted, and never cleans them up. Changed hourly, those copies grew past 16 GB. Wallpaper Changer deletes the copies it created after each change.

## Menu

- The current photo's credit (click to open it on Unsplash)

- **Next Wallpaper** (⌘N)

- **Change Every**: 15 minutes, 30 minutes, an hour, 3 hours, a day, or never

- **Allow Cache Cleanup…** (until allowed), then **Clean Up Cached Copies Now**

- **Open at Login**

- **Unsplash Access Key…**: without a key, only Google Earth images are used

- **Hide Menu Bar Icon…**: the app keeps running with no icon at all

## Hidden mode

With the icon hidden, the app still changes wallpapers on schedule. To control it:

- Open Wallpaper Changer again (Spotlight, Finder, or `open -a WallpaperChanger`) to bring the icon back

- `open wallpaperchanger://next` changes the wallpaper now

- `open wallpaperchanger://show` and `open wallpaperchanger://hide` show or hide the icon

These URLs work from Raycast, Shortcuts, or anything that can open a URL.

## Build and install

Uses Swift and [mise](https://mise.jdx.dev) tasks.

```bash
mise run install
```

This builds `WallpaperChanger.app`, installs it to `~/Applications`, removes the old LaunchAgent-based version if present, copies `UNSPLASH_CLIENT_ID` from `.env` into the app's settings if it has none, and launches it.

## Cache cleanup

macOS keeps two kinds of copies in folders that belong to its wallpaper processes:

- `com.apple.wallpaper.agent`: a full-size BMP per display, named after the SHA-256 of the image's path

- `com.apple.wallpaper.extension.image`: a JPEG copy under a random name

Those folders are protected, but the app doesn't need Full Disk Access. After the first wallpaper change, it offers to clean up and shows an Open dialog for each folder; clicking **Allow Access** grants that folder and is saved as a bookmark. This is the same approach [Aerial](https://github.com/AerialScreensaver/Aerial) uses.

Only this app's copies are deleted. Each download is kept for 2 hours, then deleted and recorded (path hash, content hash, size) for 7 days. Cache files matching a recorded path hash, or a recorded size and content hash, are removed. Wallpapers you set yourself are never touched. Downloads live in `~/Library/Application Support/WallpaperChanger/Wallpapers`.

The build is ad-hoc signed, so macOS may treat a rebuild as a new app and ask for access again.

## Tasks

| Task | What it does |
| --- | --- |
| `mise run build` | Build `.build/WallpaperChanger.app` |
| `mise run install` | Build, install to `~/Applications`, and launch |
| `mise run uninstall` | Quit and remove the app (turn off Open at Login first) |
| `mise run next` | Change the wallpaper now |
| `mise run show` | Show the menu bar icon |
| `mise run logs` | Stream the app's logs |

## License

MIT © [Ali Karbassi](https://karbassi.com)
