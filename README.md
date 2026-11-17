<p align="center">
  <img src="docs/images/dwb-skim-icon.png" alt="dwb skim app icon" width="144">
</p>

<h1 align="center">dwb skim</h1>

<p align="center">
  A native macOS app for quickly reviewing local videos with short previews, alongside images and GIFs.
</p>

<p align="center">
  <img src="docs/images/queue-review.png" alt="dwb skim main window with a video preview playing, the Skim strip above it, and the queue panel on the right" width="900">
</p>

## Overview

dwb skim is a native Swift/AppKit app for macOS 13 and newer, built for going through a pile of local media fast. Each video plays a short preview, then the queue moves on. While a file is on screen, one key adds a prefix to its name, right in your folder. Playback is powered by VLCKit.

It is local-only: no streaming, cloud library, accounts, telemetry, transcoding, or editing.

> **Current version:** v1.2.4. See [CHANGELOG.md](CHANGELOG.md) for what is new.

## Features

**Skim previews**
- A Skim strip above the video sets clip length (fixed or random), start point (beginning or random), and Skip Intro.
- **Progressive Random Skim** samples several parts of one video, in order, before moving on. Coverage runs from Light to Max.
- Turn Skim on and off with the Skim button or a double-tap of either **Option** key. With Skim off, videos play in full.

**Playback and queue**
- Local video, still images, and animated GIFs, added by drag and drop, File > Open, or Finder Open With. Folders are imported recursively.
- Sequential, Shuffle, and Weighted order, with Loop Queue, search, sorting, bookmarks, and a resizable queue panel.
- Per-window volume (up to 200%), speed, and opacity, and up to five independent windows with a Four Window Grid.
- Media that cannot be played shows a short message and the queue moves on.

**File markers**
- Two prefixes you choose in Settings, such as `keep_` and `delete_`. **N** applies the primary, **M** the secondary. Press a key again to remove its prefix, or the other key to swap it. **⌘Z** undoes the last change.
- **R** renames the current file and keeps its extension.
- **dwb skim never deletes files or moves them to the Trash.** Every file action is a rename inside the file's own folder.

**dwb+ background audio**
- Play one MP3 or M4A track on a loop across everything you review, alone or mixed with the video audio. The file is never copied.

**Settings and shortcuts**
- Eight Settings pages. Every keyboard shortcut can be changed in Settings > Shortcuts, which has a keyboard map and search.

## Default keys

| Key | What it does |
| :--- | :--- |
| **N** / **M** | Primary / secondary prefix |
| **⌘Z** | Undo the last prefix change |
| **R** | Rename the current file |
| **B** | Bookmark |
| **,** / **.** | Previous / next item |
| **Space** | Play or pause |
| **← / →** | Skim off: jump 10 seconds. Progressive Random Skim on: **→** goes to the next part |
| **Q** | Show or hide the queue panel |
| **F** | Fullscreen |
| **Option, twice** | Turn Skim on or off |

## Screenshot

<p align="center">
  <img src="docs/images/settings-skim-preview.png" alt="dwb skim Settings window showing the Skim Preview page" width="560">
</p>

## Download

Download the app ZIP from the [latest release](https://github.com/dweebzxx/dwb-skim/releases/latest), unzip it, and move `dwb skim.app` to Applications. The app is not notarized, so macOS blocks the first launch: right-click the app and choose Open, or run `xattr -dr com.apple.quarantine "/Applications/dwb skim.app"`.

## Build From Source

Requirements: macOS 13 or newer, Xcode with command line tools, `xcodegen`, and a Swift 5.9-compatible toolchain. The first build needs network access so Swift Package Manager can fetch the VLCKit package (`vlckit-spm` 3.6.0 or newer).

```sh
./dwb/scripts/clean-build-app.zsh
```

The app is written to `dist/dwb skim.app`. To run the unit tests, use `./dwb/scripts/clean-test.zsh`.

## Release and Signing

Each release includes the source code and a built app ZIP. The built app is not Developer ID signed, notarized, or sandboxed.

## Help and Feedback

Found a problem? [Report an issue](https://github.com/dweebzxx/dwb-skim/issues).

## License

MIT. See [LICENSE](LICENSE). The license covers this app's source code, not VLCKit, libVLC, or other third-party dependencies.
