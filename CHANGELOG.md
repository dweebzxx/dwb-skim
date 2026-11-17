# Changelog

All notable changes to dwb skim are listed here, newest first.

The version numbers restarted at 1.2.1 on 2026-11-15. Earlier builds used a different numbering scheme (the last was 4.2.2). Those builds are not listed.

## 1.2.4 — 2026-11-17

### Added

- **Start From Top** button on the playback rail. It restarts the queue from the first item. The default key is `P`, and you can change it.
- **Editable keyboard shortcuts.** In Settings > Shortcuts, click a key to change it, add more keys to one action, or leave an action unassigned. A conflict shows a message that names the action that already uses the key. **Restore Defaults…** clears your changes. Menus, tooltips, and Settings text show the key that is active.
- **Edit menu:** Redo (`⇧⌘Z`), Cut, Copy, Paste, and Select All.
- **Enable background audio** switch in Settings > dwb+. Turning it off keeps your chosen track and audio settings.
- A small **"dwb+ on"** label on the rail while background audio plays.

### Changed

- **Settings pages** are rebuilt with the new dwb layout and wording: Playback, Appearance & Controls (was Controls), Queue & Files, Skim Preview, dwb+, Advanced, and About. Your saved settings carry over.
- **Skim Preview:** clearer labels (Clip duration, Fixed duration, Minimum duration, Maximum duration, Start previews, Skip intro, Coverage). Settings that do not apply to your current choice are dimmed. They keep their values.
- **dwb+:** the mix options are now **Background Audio Only** and **Video + Background Audio**. The mix and volume controls turn on only when background audio is on and a track is available.
- **Advanced:** **Restore Default Settings…** now also resets your custom keyboard shortcuts. It does not delete media, queues, or bookmarks.
- **About:** shows the version and build, the license, the macOS requirement, and links to the GitHub page and issue tracker.
- **Playback rail:** Skim, Start From Top, Previous, Play/Pause, Next, Advance Segment, and Volume are now one centered group. Queue stays on the left. Bookmark, Settings, and Fullscreen stay on the right.

### Fixed

- Fixed a crash that could happen when you dragged a queue row and then cancelled the drag.

## 1.2.1 — 2026-11-15

### Changed

- **Version reset.** dwb skim is now version 1.2.1.
- **Custom prefixes** (Settings > Queue & Files) follow the same rule as dwb player. The app trims spaces, removes every trailing `_`, and adds exactly one. For example, `a`, `a_`, and `a__` all become `a_`. A blank prefix stays blank.
