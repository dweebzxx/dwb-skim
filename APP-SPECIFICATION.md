# dwb skim — Application Specification Outline

## Product definition

`dwb skim` is a native macOS 13+ AppKit application for fast, local, non-destructive review of queued video, still-image, and supported GIF media. It is designed for reviewing items in place: playback and review actions operate on local files, with no cloud library, streaming service, account system, telemetry requirement, transcoding, or media editing workflow.

The application bundle is `dwb skim.app`, bundle identifier `com.dwb.skim`, and current product version `4.2.2`. VLCKit supplies video playback.

## Primary user workflow

1. Open or drag local files and folders into a player window.
2. Expand supported folders recursively into a review queue while retaining their source roots.
3. Play video, images, and GIFs using the configured skim-preview behavior or normal playback.
4. Navigate the queue, inspect the current item, and use queue search, sorting, filtering, reorder, and rescan tools as needed.
5. Apply immediate review decisions by renaming a file in its original directory, or explicitly remove selected queue items/files through the dedicated destructive action.
6. Continue reviewing in the same window, or open additional independent player windows.

## Media and playback

### Supported review media

- Local video files played through VLCKit.
- Still images with a configurable display duration.
- Supported GIFs with a configurable loop count.
- Files and folders added by open/drop; folders are recursively expanded for supported media.

### Player window model

- Each player window owns its own VLCKit player, queue, preview scheduler, start-intent state, and optional background-audio player.
- Dock reactivation brings a current player window forward rather than creating a duplicate; **File > New Window** explicitly creates another window.
- The app uses native AppKit windows, fullscreen, titlebar behavior, menus, focus, and accessibility semantics.
- The visual policy is dark appearance for app-owned UI.

### Standard playback controls

- Queue panel toggle.
- Skim on/off toggle.
- Previous, Play/Pause, and Next.
- Video volume, including scroll-over-video adjustment and transient level/mute feedback.
- Fullscreen.
- Full-duration scrubber for inspection and relocation of a video’s active preview range.
- Compact status markers for clip duration, start position, Skip Intro, and queue order.

The logical rail order is **Queue → Skim → Previous → Play/Pause → Next → Volume → Fullscreen**. Skim-to-Volume stay visually centered as a group. There are intentionally no 10-second seek controls, Replay, repeat-current-media, standalone Shuffle control, overflow control, or persistent player-page volume slider.

### Pause and scheduling semantics

Pause applies to the complete window-owned session: video, still-image and GIF progression, background audio, preview deadlines, and automatic advancement all suspend. Resume continues a skim preview from its remaining scheduled duration rather than restarting the preview deadline. Navigation while paused changes the selected item but leaves its progress suspended until playback resumes.

### Skim preview

- Skim can be enabled or disabled explicitly from the player rail or by the app-local double-tap Option shortcut while a player window is active.
- When enabled, configured Clip Duration and Start Position settings govern later media assignments; enabling it does not seek or restart the current item.
- Video preview ranges can start at the beginning or a valid random range.
- Skip Intro defines the lower bound for preview starts. Beginning starts at that boundary; Random selects a valid range that still leaves room for the configured preview duration.
- A logical media assignment owns a stable assignment token and start intent. This protects media-start behavior from unstable VLCKit wrapper identity.
- Turning Skim off cancels only Skim-owned timing and leaves the current media playing from its current position.

## Queue and file review

### Queue behavior

- Sequential order follows the current manual or sorted traversal order.
- Shuffle uses randomized cycles.
- Weighted prioritizes media that has waited longest since playback.
- Loop Queue controls whether traversal wraps.
- The queue panel supports current-item indication, search, sorting, bookmark filtering, manual reorder, folder rescan, clear queue, and queue selection.
- Queue rows show filename, duration, and file size; the active item is visually identified.
- The queue panel is hideable, uses a flat compact dark presentation, and is hidden in fullscreen.

### Review rename actions

- `K` applies the `keep_` filename prefix.
- `D` applies the filename-only `delete_` prefix; this is not Trash deletion.
- `R` applies the configured custom rename/prefix action.
- `Z` undoes the most recent successful review rename.
- All app-owned renames happen immediately in the source directory, preserve the original extension, and reconcile the existing queue item in place so traversal, current selection, and queue ordering remain coherent.

### Explicit deletion

**Delete Selected** in the queue footer is distinct from the `delete_` rename shortcut. It moves selected media to macOS Trash and is the explicit destructive file operation.

## Skim+ background audio

- Settings accepts one MP3 or M4A background track through a security-scoped bookmark.
- Every player window owns an independent looping background-audio player.
- The track may continue across queue transitions and over video, images, and GIFs.
- **Uploaded Audio Only** keeps video playback while temporarily suppressing video audio.
- **Video + Uploaded Audio** plays video audio and uploaded audio together.
- Background-audio volume is independent of video volume.
- Missing, moved, unsupported, or inaccessible tracks present an unavailable state without interrupting normal review.

## Settings

Settings is a native dark AppKit window with a text sidebar and scrollable pages. It restores the last selected category and synchronizes its shared preferences with the inline player strip and open player windows.

1. **Playback** — playback rate, video-audio normalization, and related playback preferences.
2. **Skim Preview** — Skim enablement, preview duration, start behavior, Skip Intro, still-image timing, and GIF loop configuration.
3. **Skim+** — bookmarked background-audio selection, mix mode, and background-audio volume.
4. **Controls** — player control visibility/interaction preferences.
5. **Queue & Files** — custom prefixes, queue order, Loop Queue, and queue-panel behavior.
6. **Shortcuts** — review and player keyboard shortcut reference.
7. **Advanced** — operational and UI behavior options.
8. **About** — app identity, version/build, purpose, platform, interface, playback backend, links, and copyright.

All settings use shared normalized defaults and notification flow; changes synchronize across relevant open windows. Numeric controls commit at the end of editing so typed values are not rewritten mid-entry.

## Interface and accessibility

- Programmatic AppKit only; no SwiftUI, storyboards, XIBs, or Interface Builder files.
- Native controls, system font, SF Symbols, visible keyboard focus, dynamic system text colors, and AppKit accessibility labels/values are used throughout.
- The suite uses a restrained dark presentation with semantic color roles: Periwinkle for active/current emphasis, Dark Teal for configured rename emphasis, Burnt Orange for `delete_`/secondary review meaning, and system status treatment for caution/destructive states.
- Settings pages scroll rather than clip at smaller window sizes.
- Hidden controls preserve appropriate responder-chain, keyboard traversal, and accessibility behavior.
- Reduced Motion and increased-contrast behavior are supported through the native presentation system.

## Data, privacy, and safety boundaries

- Media remains local; the app does not upload, transcode, or copy selected background audio.
- Background-audio access uses macOS security-scoped bookmarks.
- Review renames intentionally change local filenames immediately; the undo action is limited to the most recent successful review rename.
- File deletion is separated from filename prefixing and exposed as an explicit queue action.
- The application does not provide media trimming/editing, packaging, signing, notarization, or release workflows.

## Engineering architecture

### Source layout

- `dwb/dwb-skim/App/` — lifecycle, defaults, bookmark-backed access, Settings, shared `SkimSettingsStore`, and background-audio settings.
- `dwb/dwb-skim/Player/` — per-window playback, queue/review behavior, preview planning and scheduling, player controls, and background audio.
- `dwb/dwb-skim/Resources/` — Info.plist and app icon assets.
- `dwb/dwb-skimTests/` — deterministic unit tests for policies, planners, state, settings, queue behavior, and scheduling.
- `dwb/project.yml` — authoritative XcodeGen target, version, package, source, test, and resource definition.

### Important invariants

- Do not compare Objective-C wrapper identity returned from `VLCMediaPlayer.media`; use the app’s assignment-token model for logical ownership.
- Preserve `SkimPreviewSessionScheduler` suspended remaining-duration semantics.
- Keep playback and background-audio state owned per window; do not introduce shared mutable player state.
- `dwb/dwb-skim.xcodeproj` is generated from `dwb/project.yml`, not hand-maintained.

## Verification baseline

- Canonical Debug build: `xcodebuild -project dwb/dwb-skim.xcodeproj -scheme dwb-skim -configuration Debug -destination 'platform=macOS' build`
- Clean app build: `nice -n 10 ./dwb/tools/clean-build-app.zsh`
- Clean test suite: `nice -n 10 ./dwb/tools/clean-test.zsh`
- Verified P28 baseline: 323 tests passed, 0 failures; freshly built `dist/dwb skim.app` launched successfully.
