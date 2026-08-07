# dwb skim Product Plan

## Product Definition

`dwb skim` is a dark, native macOS skim-review application for rapidly reviewing local video, still-image, and GIF queues. The primary workflow is previewing a bounded range, classifying or renaming the source file immediately, and moving to the next queue item without entering an editing timeline.

## Implemented Experience

### Player

- A balanced 54-point interactive Skim Settings strip spans the full window above both media and queue, redistributing its groups as the window resizes.
- Its stable order is Clip duration, Start position, Skip intro, Image duration, GIF loops, Queue order, a native Loop queue switch, and Settings.
- Clip duration supports Fixed and Random ranges; zero fixed duration retains full-file behavior. Clip Duration and Start Position are disabled while Skim is off, without changing their configured values.
- Start position supports Beginning and Random, with a normalized Skip Intro value.
- Still images use a persistent positive duration in seconds (default `3` seconds), while GIFs advance after a persistent integer number of completed animation loops (default `1` loop).
- Queue order supports Sequential, Shuffle, and waited-since-played Weighted behavior plus Loop Queue.
- The video overlay is a translucent 68-point surface with Previous, Skim, Queue, Play/Pause, Next, video Mute/Unmute, and Fullscreen; its leading order is Previous → Skim → Queue.
- Skim defaults on and can be toggled from the overlay or by double-tapping either Option key while the app and player window are active. Turning it off cancels Skim timing without seeking, restarting, pausing, or advancing current media; future assignments use non-Skim playback until it is re-enabled.
- The single video scrubber represents full media duration, shows the active preview range and progress, and relocates/clamps that range on click or drag without a persistent Preview timestamp row.
- Scroll-based video volume adjustment presents a transient level/mute meter that fades automatically; no persistent player-page volume control exists.
- A restrained separator appears between video and queue only while the queue is visible.
- Replay, standalone Shuffle controls, and fixed-duration rewind/fast-forward commands are removed.

### Queue And Review

- The narrow hideable queue panel uses one flat compact list without thumbnails or separate playback sections.
- Each row presents filename, duration, and file size. The current item has an active fill, left marker, and play indicator.
- `keep_`, `delete_`, custom rename, and undo remain immediate same-directory file renames with extension preservation. A renamed queue item keeps its stable identity, exact lineup position, current/selection state, and playback ownership across rename and filesystem reconciliation.
- `delete_` is filename classification only. Delete Selected is a confirmed move-to-Trash operation.
- Search, sorting, bookmarks, manual reorder, rescan, Clear Queue, and empty-queue behavior remain active.
- The first explicitly supplied folder root remains fixed between the list and footer while the list scrolls. Individual-file queues retain their existing source semantics.
- Filename accents are `keep_` Periwinkle `#4C62A8`, `delete_` Burnt Orange `#8F4218`, and Rename/configured custom-rename presentation Dark Teal `#254F58` through one semantic rename token.

### Settings And Shortcuts

- The Settings order is Playback, Skim Preview, Skim+, Controls, Queue & Files, Shortcuts, Advanced, About.
- The inline strip and Settings use a shared normalized persistence store and notifications, including updates across open player windows.
- A shared 36-point leading inset, label/control grid, row spacing, leading-constrained maximum width, and page scrolling keep all eight pages aligned while leaving extra width to the right.
- Playback owns image seconds, GIF loops, and the default-off Normalize video audio toggle; Skim Preview remains video-only.
- About displays the bundled runtime application icon beside version, framework, backend, and platform information.
- Active playback, media acceptance, preview, queue, prefix, window, diagnostics, bookmark, and reset controls remain organized on their owning pages.
- Review shortcuts are `K`, `D`, `R`, and `Z`; navigation uses `[` and `]`; queue toggle uses `Q`; playback uses Space, `M`, and `F`.
- Review shortcuts work from the queue table but are suppressed while text and numeric fields accept input.

### Skim+

- One external MP3 or M4A file is persisted through a security-scoped bookmark without copying or modifying it.
- Uploaded Audio Only suppresses video audio while preserving the stored video mute/volume preference.
- Video + Uploaded Audio mixes both sources with independent background volume.
- Each player window owns its own continuously looping audio player and security-scoped access lifecycle.
- Background audio continues across queue transitions and media kinds, and stops on clear, replacement, unavailability, or owning-window close.
- Stale bookmarks are refreshed when possible; missing, moved, denied, unsupported, and decode failures remain nonfatal to media playback.
- Optional video normalization uses per-window VLCKit momentary loudness measurements and live equalizer preamplification. It never enters the separate Skim+ `AVAudioPlayer` signal path or changes its playback position or volume.

### P14.1 Reliability Correction

- Each eligible video session owns one monotonic skim-preview scheduling state and one effective deadline, with `.playing` as the normal readiness signal and a bounded session-checked fallback for reused-player transitions that do not emit it.
- Preview duration is resolved once per session. Late media length may refine the seek/range and shorten a deadline for short media, but missing metadata cannot leave a configured preview playing indefinitely.
- Deadline, natural-end, manual-navigation, replacement, and cancellation callbacks share session and queue-item checks so only one transition can win.

### P15 Playback-Session Corrections

- Skip Intro is the exact beginning-mode offset and the lower bound for Random. Random selection retains one value per media session and leaves room for the already-selected fixed or random preview duration; short media collapses to the only safe clamped start instead of reverting to zero.
- Every video owns a start intent bound to its playback-session ID, queue item, and concrete VLC media object. A seek setter is logged as a request only; observed playback time confirms it, while bounded same-session retries recover from readiness resets without changing the random choice or overwriting later user scrubbing.
- Pause is window-session state: video, still-image timing, GIF frames, Skim+ audio, preview deadlines, delayed completion, natural-end fallback, and watchdog advancement suspend together. Loading another item preserves pause, and resume continues the stored remaining duration without duplicating seeks, audio starts, deadlines, or queue transitions.

## Architecture Boundaries

- Swift, programmatic AppKit, VLCKit, and macOS 13+ remain the platform baseline.
- Video playback, preview session state, queue state, and background audio remain per-window.
- `dwb/project.yml` remains the XcodeGen source of truth.
- The app stays local-only and dark; no SwiftUI, storyboards, global playback singleton, media transcoding, trimming, editing timeline, or added runtime dependency is planned.

## Remaining Product Work

- Continue real-media product verification on representative quiet/loud videos, still-image and GIF timing, MP3/M4A Skim+ modes, simultaneous player windows, resizing/fullscreen, and moved-file recovery.
- Define packaging, signing, notarization, and release interfaces only when distribution requirements are approved; none are currently part of the repository contract.
- Address compatibility or usability defects found through normal product use without reintroducing removed controls or creating a separate ceremonial sign-off milestone.
