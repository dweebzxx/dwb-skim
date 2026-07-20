<h1 align="center">dwb skim</h1>

<p align="center">
  A native macOS skim-review application for rapidly reviewing local media queues.
</p>

## Overview

`dwb skim` is a focused Swift/AppKit application for reviewing local video, image, and GIF files on macOS 13 and newer. It uses VLCKit for video playback, keeps playback and background-audio ownership per window, and performs all review/file operations locally.

The app does not stream, sync to a cloud service, transcode media, or copy selected background-audio files.

## Review Workflow

- Open or drop files and folders; supported folders expand recursively while retaining the original root in the queue panel.
- Configure video preview duration and start behavior, still-image duration in seconds, GIF loop count, Sequential/Shuffle/Weighted queue order, and Loop Queue from the responsive strip above the player.
- Relocate the active preview range by clicking or dragging the full-duration scrubber.
- Apply `keep_` with `K`, apply the filename-only `delete_` action with `D`, rename with `R`, and undo the last review rename with `Z`.
- Use **Delete Selected** in the queue footer to move media to Trash. This is intentionally separate from the `delete_` filename prefix.

Review renames happen immediately in the source directory. Custom rename preserves the original extension, and every app-owned rename updates the existing queue item in place: the complete Sequential, Shuffle, or Weighted lineup, current item, and queue selection stay where they were. Filename styling uses Periwinkle `#4C62A8` for `keep_`, Dark Teal `#254F58` for Rename and configured custom-rename prefixes, and Burnt Orange `#8F4218` for `delete_`.

## Player And Queue

The player overlay’s logical order is **Queue → Skim → Previous → Play/Pause → Next → Volume → Fullscreen**. Queue remains at the far left and Fullscreen at the far right; Skim through Volume are independently centered as a group. Compact status markers above the controls show Clip Duration, Start Position, Skip Intro, and Queue Order. Clip Duration and Start Position remain visible but muted when Skim is off. The top Skim controls can be hidden with their chevron and restored from the small top-edge handle without changing settings or playback. The Skim button exposes an explicit On/Off state and shares its action with the application-local **Double-tap Option** shortcut; either Option key works only while the app and a player window are active. Option-modified typing and commands remain untouched. Scrolling over video still adjusts video volume and briefly shows a non-interactive level/mute meter; there is no persistent player-page volume slider. The full-duration scrubber highlights and relocates the active video preview range without a persistent timestamp row. Removed controls such as Replay, standalone Shuffle, and fixed-duration rewind/fast-forward commands are not exposed or persisted.

Clicking the Dock icon while `dwb skim` is already running brings the current player window forward instead of opening a duplicate: the key player window is preferred, otherwise the most recently active one, and a minimized or hidden window is restored in place with its window state, queue, and playback intact. A Dock click creates a player window only when no player window exists at all. **File > New Window** still opens an additional player window on demand.

Skip Intro excludes the configured number of seconds from the beginning of every video. With Beginning selected, playback starts at that boundary; with Random selected, the boundary becomes the lower limit of a random range whose upper limit leaves room for the chosen fixed or random preview duration. Each video session retains one media-bound start intent until VLCKit confirms the requested offset, with bounded same-session retries if a reused or fresh player resets to zero.

Turning Skim off cancels only Skim-owned preview timing and lets the current media continue at its existing position. Subsequent video assignments use normal full playback until Skim is enabled again; enabling it does not seek or restart the current item, and preserved Clip Duration and Start Position settings apply to the next assignment. Clip Duration and Start Position controls are gray and unavailable while Skim is off; Skip Intro and unrelated player controls remain available.

Play/Pause controls the complete window-owned session. Pausing freezes video, still-image and GIF progression, Skim+ audio, preview deadlines, and pending automatic advancement. Navigation remains available while paused, but the selected item and its countdown stay suspended until resume, which continues with the remaining duration.

The hideable right queue panel uses a flat compact list with filename, duration, and file size, separated from the media by a restrained divider only while the queue is visible. The current item remains in that list with an active background, left indicator, and play indicator. Search, sorting, bookmark filtering, manual reorder, folder rescan, Clear Queue, and immediate review renames remain available.

Queue order modes are:

- **Sequential**: current manual/sorted traversal order.
- **Shuffle**: randomized queue cycles.
- **Weighted**: prioritizes media that has waited longest since playback.

## Skim+

Settings > Skim+ accepts one MP3 or M4A background track using a macOS security-scoped bookmark. Each player window owns an independent continuously looping audio player. The track continues across queue transitions and over video, images, and GIFs.

The two mix modes are:

- **Uploaded Audio Only**: video playback continues while video audio is temporarily suppressed.
- **Video + Uploaded Audio**: video and uploaded audio play together.

Background-audio volume is independent from video volume and is available only on the Skim+ page. Missing, moved, unsupported, or inaccessible files produce an unavailable state without interrupting normal media review.

## Settings

The dark Settings window uses this sidebar order:

1. Playback
2. Skim Preview
3. Skim+
4. Controls
5. Queue & Files
6. Shortcuts
7. Advanced
8. About

The Settings window restores the last selected category and uses one trailing-label, leading-control form grid per scrollable detail pane; controls retain their existing immediate persistence and notification behavior. The inline strip and Settings window share the same normalized `UserDefaults` state and notification path, so Skim enabled state, image seconds, GIF loops, queue order, and the native Loop queue switches synchronize across existing player windows. Playback Settings also provides persistent, default-off **Normalize video audio**, which adapts VLCKit video gain in real time and never processes or changes Skim+ background audio. The four read-only playback markers span the full playback rail between Queue and Fullscreen, sharing its horizontal bounds while the five middle controls remain centered.

## Requirements

- macOS 13 or newer
- Xcode with command line tools
- Swift 5.9-compatible toolchain
- Network access for Swift Package Manager on the first build
- `xcodegen` to regenerate `dwb/dwb-skim.xcodeproj` from `dwb/project.yml`

## Build And Test

From the repository root:

```sh
dwb/tools/generate-project.zsh
dwb/tools/clean-build-app.zsh
dwb/tools/clean-test.zsh
```

`clean-build-app.zsh` copies the verified app to `dist/dwb skim.app`. The canonical direct app build is:

```sh
xcodebuild -project dwb/dwb-skim.xcodeproj -scheme dwb-skim -configuration Debug -destination 'platform=macOS' build
```

### Video audio normalizer verification

Run this deterministic, fixture-free check from the repository root:

```sh
./dwb/tools/verify-volume-normalizer.zsh
```

It compiles and evaluates the production normalization policy with synthetic LUFS measurements, printing quiet/target/loud gain decisions plus clamp, bypass, invalid-measurement, and repeatability checks. It verifies the policy and equalizer gain command that the app applies, not decoded or speaker-rendered acoustic output.

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
docs/
  skim-m1-plan.md
```

`dist/`, `.tmp/`, DerivedData, build logs, archives, signing material, and local user state are ignored by git.

## License

This repository is licensed under the MIT License; VLCKit, libVLC, and other third-party dependencies retain their own licenses.
