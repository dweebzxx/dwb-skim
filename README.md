<p align="center">
  <img src="docs/images/dwb-skim-icon.png" alt="dwb - skim app icon" width="144">
</p>

<h1 align="center">dwb - skim</h1>

<p align="center">
  A native macOS media player baseline for local queueing, multi-window playback, and future skim-focused iteration.
</p>

<p align="center">
  <img src="docs/images/dwb-skim-hero.png" alt="dwb - skim main playback window with bottom rail controls" width="900">
</p>

## Overview

`dwb - skim` is a native Swift/AppKit macOS app targeting macOS 13 and newer. This repository now uses the `dwb-skim` project identity while preserving the donor app's current playback architecture, queue model, and VLCKit integration as the baseline for future skim-specific work.

Playback is powered by VLCKit through Swift Package Manager. The current app remains local-only: it does not provide streaming, cloud sync, telemetry, transcoding, or media-library management.

## Current State

- Project slug, Xcode project, app target, test target, and shared schemes use `dwb-skim`.
- The public product name is `dwb - skim`.
- Bundle identifiers use the existing `com.dwb` owner prefix with skim-specific suffixes.
- The codebase is still behaviorally close to the donor app; this pass only completes identity migration.
- Skim-specific review behavior is planned in [`docs/skim-m1-plan.md`](docs/skim-m1-plan.md); this pass establishes only the accent/status color token baseline (Dark Teal `#254F58` as primary accent, Burnt Orange `#8F4218` for delete, Periwinkle `#4C62A8` for rename/other).

## Features

### Playback

- Native Swift and AppKit macOS application with a programmatic UI.
- VLCKit-backed local video playback.
- Drag-and-drop, Finder/Open With, Dock open, menu open, and recursive folder expansion for supported local media files.
- Play/pause, previous/next, configurable rewind/forward skip controls, scrubber seeking, fullscreen, Fit/Fill/Stretch scale modes, Keep Window On Top, and optional titlebar auto-hide.
- Per-window volume, mute, playback speed, opacity, and playback state.
- Repeat One plus queue order settings for Sequential, Shuffle, Weighted (waited-since-played), and Loop Queue.
- Skim Preview settings for fixed or random per-item preview duration, random duration bounds, start position, and skip-intro.

### Queue

- Queue page with filename, duration, file size, search/filter, bookmark filter, and total queue duration.
- Manual queue ordering by row drag plus multiple sort modes.
- Settings-controlled queue playback order: Sequential, Shuffle, Weighted (favoring items that have waited longest since playback), plus Loop Queue.
- Multi-select queue operations, removal actions, and queue rescan support.
- Reveal in Finder, rename-current-file, and bookmark actions integrated into the app UI.

### Windows And Controls

- Multiple independent player windows, each with its own VLCKit player state.
- Four Window Grid layout for arranging four player windows.
- Unified bottom rail with transport, bookmark, prefix, and fallback menu actions.

## Screenshots

The README still references screenshot assets, but the image files are currently missing from `docs/images/` in the working tree. Their expected skim-era names are:

- `docs/images/dwb-skim-icon.png`
- `docs/images/dwb-skim-hero.png`
- `docs/images/dwb-skim-four-window-grid.png`
- `docs/images/dwb-skim-queue.png`
- `docs/images/dwb-skim-settings.png`

## Requirements

- macOS 13 or newer
- Xcode with command line tools
- Swift 5.9-compatible toolchain
- Network access for Swift Package Manager on first build so Xcode can fetch the pinned VLCKit dependency
- Optional: `xcodegen` to regenerate `dwb/dwb-skim.xcodeproj` from `dwb/project.yml`

## Build From Source

Use the public project helpers from the repository root:

```sh
dwb/tools/generate-project.zsh
dwb/tools/clean-build-app.zsh
```

`clean-build-app.zsh` builds the app via `xcodebuild` and then copies the resulting bundle to `dist/dwb - skim.app` at the repository root for easy access.

To run the unit tests:

```sh
dwb/tools/clean-test.zsh
```

The equivalent direct clean commands are:

```sh
xcodebuild -project dwb/dwb-skim.xcodeproj -scheme dwb-skim -configuration Debug -destination 'platform=macOS' -derivedDataPath .tmp/DerivedData-dwb-skim-app clean build
xcodebuild -project dwb/dwb-skim.xcodeproj -scheme dwb-skimTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .tmp/DerivedData-dwb-skim-tests clean build
xcodebuild -project dwb/dwb-skim.xcodeproj -scheme dwb-skimTests -configuration Debug -destination 'platform=macOS' -derivedDataPath .tmp/DerivedData-dwb-skim-tests clean test
```

## Project Structure

```text
dwb/
  project.yml
  dwb-skim.xcodeproj/
  dwb-skim/
    App/
    Player/
    Resources/
  dwb-skimTests/
docs/images/
```

`dist/`, `.tmp/`, `DerivedData/`, build logs, archives, package outputs, signing material, and local user state are intentionally ignored by git.

## Provenance

This repository was extracted from the `dwb player` donor app and then renamed to `dwb-skim` / `dwb - skim`. Historical provenance remains in [README-dwb-skim-donor.md](README-dwb-skim-donor.md) and [DONOR_MANIFEST.md](DONOR_MANIFEST.md).

## License

MIT. See [LICENSE](LICENSE).

This repository's MIT license applies to this app's source code, not to VLCKit, libVLC, or other third-party dependencies.
