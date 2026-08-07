# dwb player UI Specification

**Version:** 1.0 · **Date:** 2026-07-26  
**Product reference:** `dwb player` for macOS 13+  
**Audience:** AppKit designers and engineers building a sibling local-media player in the same suite.

## 1. Purpose, scope, and authority

This is the implementation-ready specification of the **currently shipped** `dwb player` UI system. It defines visual and interaction consistency for sibling apps; it does **not** require feature parity, identical content, or a copied layout. Use it to preserve the family resemblance while letting the sibling product's media type, task flow, and information hierarchy determine its composition.

Non-goals: it does not prescribe streaming, cloud, library, account, telemetry, or other product expansion; it does not describe retired or non-shipped UI patterns; and it is not a redesign proposal.

Resolve conflicts in this order:

1. The authoritative color-system asset: [`assets/Asset_Color_System.md`](../.private/assets/Asset_Color_System.md).
2. This specification.
3. The sibling app's approved product requirements.
4. The current source implementation for an unresolved detail.

### Transfer model

| Classification | Keep or change | Current `dwb player` reference |
| --- | --- | --- |
| **Keep consistent across the suite** | System font and SF Symbols; restrained dark surfaces; semantic color roles; native AppKit controls/windows; visible keyboard focus; compact rounded control language; sidebar-led Settings; clear status, destructive, and selection treatment. | `RailButton`, `QueuePageView`, and `SettingsWindowController`.
| **Adapt to the sibling app** | Product name/icon; player/content composition; which controls are essential; list/queue data and columns; Settings pages and copy; transient message content; shortcut inventory. | The video surface, Queue Page, media-specific controls, and queue/file settings are `dwb player` implementations of the system—not a required sibling layout.
| **Do not copy automatically** | Prefix rename controls, local-file rename/delete semantics, image/GIF playback rules, queue traversal rules, folder rescan, playback-rate controls, volume overdrive, and exact menu shortcuts. | These are tied to `dwb player`'s local-media behavior and must exist only when the sibling app has the same approved product need.

## 2. Design principles

- **Native macOS/AppKit behavior.** Windows, menus, keyboard focus, sheets, scrolling, and accessibility use AppKit rather than a custom imitation.
- **Local-media focus.** Controls and recovery copy explain local file actions plainly; destructive queue actions distinguish queue removal from file deletion.
- **Unobstructed content.** The media surface leads; rails and overlays occupy edges or temporary, stateful positions.
- **Restrained dark graphite surfaces.** Dark layers, quiet white alpha keylines, and material separate regions without decoration-heavy cards.
- **Semantic brand accents.** Periwinkle carries selected/current/bookmarked and primary-action emphasis; teal and orange identify the two configured prefix roles; status colors retain status meaning.
- **Compact controls with clear state.** Icon-first buttons expose hover, pressed, toggled, focused, disabled, tooltip, and accessibility state.
- **One coherent playback control surface.** The bottom rail is the shipped playback control surface.
- **Predictable windows and keyboard behavior.** Each player window maintains its own playback/queue state; Settings is independently movable and normally ordered above player windows only while the app is active.
- **Accessibility and motion preferences.** Hidden UI leaves hit testing, key traversal, and accessibility; increased contrast and Reduce Motion alter presentation without removing information.

## 3. Foundations and design tokens

### Typography and iconography

Use the macOS system font family. Use SF Symbols through `NSImage(systemSymbolName:)` for icon-only controls; configure symbols at the semantic control size and medium/semibold weight where the source does. Do not introduce a custom font.

| Role | Current token / rule | Source |
| --- | --- | --- |
| Window title | System font at `NSFont.systemFontSize`, regular; centered and middle-truncated. | `PlayerWindowController.installCenteredTitleLabel` |
| Queue title | 16 pt, semibold, Periwinkle. | `QueuePageView.setupViews` |
| Queue row title / metadata | 12.5 pt medium title (semibold when current); 10.5 pt monospaced-digit regular metadata; semantic text alpha varies by hierarchy. | `QueuePageCell.configure` in `QueuePageView.swift` |
| Queue section label | 10 pt bold, uppercase-style section content such as `NOW PLAYING`. | `QueuePageSectionCell` and `QueueDisplayProjection.sectionedRows` |
| Queue search/sort | 11 pt search; 10.5 pt sort title. | `QueuePageView.setupViews` |
| Rail time | 10 pt monospaced digits, regular. | `BottomRailView.setupViews` |
| Shortcut badge | 8 pt monospaced system, semibold. | `ShortcutKeyBadge` in `RailButton.swift` |
| Settings sidebar | 13 pt regular; selected is 13 pt semibold. | `SettingsSidebarItemButton.updateAppearance` |
| Settings section / row / helper | 11 pt semibold section; system body size row; small system size helper. | `SettingsWindowController.buildSection` / `buildRow` |
| About | Name 20 pt semibold; version 11.5 pt; description 12 pt; metadata 11 pt; copyright 10.5 pt. | `SettingsWindowController.buildAboutSection` |
| Transient banner | 13.5 pt semibold, center-aligned, middle-truncated. | `TransientBannerView.setupViews` |
| Intake recovery | 13.5 pt semibold title; 11.5 pt message; 10.5 pt details; 11 pt actions. | `IntakeRecoveryView.setupViews` / `rebuildActionButtons` |
| Volume HUD | 14 pt monospaced digits semibold value; 8 pt semibold caption; 8 pt monospaced ticks. | `VolumeBarView` label factories |

### Color roles

The authoritative asset supplies the following raw values. Do not add raw colors to a sibling app; select a semantic role and use the authoritative color or a system dynamic color.

| Semantic role | Authoritative value | Current use | Source |
| --- | --- | --- | --- |
| Suite accent / active / current / bookmark | Periwinkle `#4C62A8` | Current queue row, selected Settings sidebar, recovery primary action, active rail fill. | `PlayerBrandColors.periwinkle` in `RailButton.swift` |
| Accent keyline / focus foreground | Periwinkle 300 `#9AAAD8` | Focus outline, bookmark tint, volume HUD normal fill, recovery action keyline. | `PlayerBrandColors.periwinkleLight` |
| Primary configured-prefix role | Dark Teal 500 `#488FA0` | Primary prefix button, prefix highlighting, rename confirmation. | `PrefixBrandColors.primaryCustomPrefixColor` |
| Secondary configured-prefix role / volume overdrive | Burnt Orange 300 `#D4906A` | Secondary prefix; volume above 100%. | `PrefixBrandColors.secondaryCustomPrefixColor` |
| Caution | Dark Ochre `#A87820`; readable foreground Dark Ochre 300 `#E0C060` | Warnings and intake recovery borders/foreground. | `PlayerBrandColors.darkOchre` / `darkOchreLight` |
| Destructive / failure | Crimson `#B03828`; readable foreground Crimson 300 `#E09888` | Queue removal and clear-queue actions; failure role where applicable. | `PlayerBrandColors.crimson` / `crimsonLight` |
| Shared structural edge | Border / Axis `#C4BDB5` at 24% alpha | Queue-panel shared edge. | `QueuePageView.Palette.sharedEdge` |
| Dynamic system text | `labelColor`, `secondaryLabelColor`, `tertiaryLabelColor` | Settings, About, and transient semantic text. | `SettingsWindowController`, `IntakeRecoveryView` |

The current queue uses calibrated graphite layers rather than fixed asset hex values: panel white 10.5%, header 8.5%, column-header 12.5%, and footer 8%; quiet separators use white at 7.5%. The rail and compact controls use transparent/white-alpha fills and keylines over `.hudWindow` material. Preserve those relationships, not an invented global hex substitute. (`QueuePageView.Palette`; `TransportControlsView`; `RailButton`.)

### Surface, spacing, radius, and elevation

| Token or recurring rule | Current value / behavior | Source |
| --- | --- | --- |
| Main player baseline | 960 × 540; minimum 480 × (180 + 48 rail height). | `PlayerWindowController.buildWindow` |
| Bottom rail | 84 pt windowed; 80 pt fullscreen. | `TransportControlsView.performLayout` |
| Queue panel | Right-side 45% of window width, minimum 260 pt; source comment describes intended 35–45% range. | `PlayerWindowController.layoutPlayerViews`; `QueuePageView` class comment |
| Queue regions | 48 pt header, 36 pt footer, 66 pt item row. | `QueuePageView` layout constants / `setupViews` |
| Queue header edge rhythm | 10 pt edge pad, 8 pt adjacent-control gap, 12 pt title-to-search pill gap. | `QueuePageView.layout` |
| Settings navigation | 160 pt sidebar; 136 × 32 pt items; 12 pt side insets; 4 pt item stack gap. | `SettingsWindowController.buildUI` |
| Settings content rhythm | 28 pt horizontal, 20 pt vertical content margins; 22 pt between groups; 9 pt within a section; 10 pt after section title; 14 pt label-to-control gap; 4 pt label/helper gap. | `SettingsWindowController.buildSectionContainer`, `buildSection`, `buildRow` |
| Standard compact corners | 3 pt shortcut badge; 6 pt small recovery action / header-control cap; 7 pt Settings sidebar; 10 pt banner/recovery; 12 pt queue/ footer pills and volume HUD. | `ShortcutKeyBadge`, `IntakeRecoveryView`, `SettingsSidebarItemButton`, `TransientBannerView`, `QueuePageView`, `VolumeBarView` |
| Borders | 1 pt by default; focused controls become 2 pt only with Increase Contrast. | `RailButton.updateAppearance`, `QueueHeaderSymbolButton.updateAppearance`, `SettingsSidebarItemButton.updateAppearance` |
| Volume HUD elevation | Black 82% background, 1 pt Periwinkle-light 34% border, black 70% shadow with 0.72 opacity, radius 10, offset `(0,-3)`. | `VolumeBarView.setupBackground` |
| Stable transient timing | Title overlay is visible 5 s then fades 0.5 s; rename confirmation dismisses after 2.5 s and fades 0.18 s unless Reduce Motion; volume HUD hides after 1.9 s with 0.16/0.24 s normal in/out (0.08/0.12 s Reduce Motion). | `PlayerWindowController.showVideoTitleOverlay` / `showRenameConfirmation`; `VolumeBarView` |

## 4. Main player window

`PlayerWindowController` owns one native titled, closable, miniaturizable, resizable `NSWindow` and one playback session. Its title is visually replaced by a centered, middle-truncated system label while standard traffic lights remain available in normal windowed chrome. The window does not tab and is not restorable. Keep-at-top is an explicit user option (`.floating`); otherwise it is normal level. (`PlayerWindowController.buildWindow`, `installCenteredTitleLabel`, `applyKeepAtTop`.)

Windowed mode can use the standard titlebar or the existing approved edge-to-edge chrome setting. Fullscreen is native AppKit fullscreen. In fullscreen, the media and transport occupy the full content bounds and the Queue Page is hidden; exiting fullscreen recalculates from current content bounds rather than stale screen geometry. (`PlayerWindowController.applyWindowedChromeModeIfNeeded`, `layoutPlayerViews`.)

### Conceptual composition

```text
windowed
┌──────────────────────── media/content area ────────────────────────┬─ Queue Page ─┐
│ centered titlebar / traffic lights                                 │ header       │
│                                                                     │ search/actions│
│ video, image, or GIF surface                                       │ sectioned list│
│ transient title / rename / recovery feedback (only when needed)   │ footer       │
│                                                       volume HUD    │              │
│ unified bottom playback rail (edge-aligned; auto-hides when safe) │              │
└───────────────────────────────────────────────────────────────────┴──────────────┘
```

### Transferable rules

- Keep the content surface visually primary. Feedback is temporary and is anchored away from the rail; persistent recovery has a state reason.
- Use a single edge-aligned playback rail, not a second floating transport surface.
- A sibling app may use a different content surface, omit a queue/list, or allocate a different adaptive panel proportion. It should preserve clear surface boundaries and calculate from live content bounds.
- In narrow windowed layouts, retain essential actions through the native More menu if a dedicated rail button is hidden. The sibling's essential-action set may differ.

### Current overlays and chrome

- The playback title overlay sits top-center of the video area, is 38 pt below 560 pt width and 42 pt otherwise, caps at 800 pt / available width, uses a black 38% rounded background (8 pt) and white semibold text with a black shadow. It is an announcement, not an input surface. (`PlayerWindowController.showVideoTitleOverlay`, `positionVideoTitleOverlay`.)
- The rename confirmation is top-center of the video area: 38 pt high, minimum 220 pt, 14 pt horizontal inset, 10 pt radius, material background, teal semantic foreground and keyline. It is pointer-transparent and non-focusable. (`TransientBannerView`; `PlayerWindowController.positionRenameConfirmation`.)
- The current transport auto-hide system keeps the rail visible during paused, scrubbing, focused, VoiceOver, menu/popup, buffering/failure, and fullscreen-transition states; reduced motion uses opacity/immediate changes instead of scale/slide effects. (`RailAutohideController` as used by `TransportControlsView`; design criteria.)

## 5. Playback controls and buttons

### Control language

Use compact, rounded, icon-first `RailButton` controls on the unified rail. SF Symbol point sizes are semantic: primary play/pause is larger than adjacent navigation; utility symbols are smaller; labels replace symbols only for configured prefix actions. The current rail covers queue, configured prefix actions, navigation, play/pause, time/scrubber, mute/volume, shuffle, repeat, bookmark, More, Settings, and fullscreen; exact availability adapts to state and user settings. (`BottomRailView`, `TransportControlsView`.)

| State | Current visual and semantic behavior | Source |
| --- | --- | --- |
| Normal | White or semantic icon tint; clear fill/keyline. | `RailButton.updateAppearance` |
| Hover | White 13% fill (24% for emphasized); quiet white border; toggled controls use stronger semantic fill. | `RailButton.updateAppearance` |
| Pressed | White 24% fill or stronger semantic fill; stronger keyline. | `RailButton.updateAppearance` |
| Toggled / selected | Semantic fill 20% (28% hovered) and semantic keyline; accessibility value `on` / `off`. | `RailButton.isToggled` / `updateAppearance` |
| Keyboard focus | Periwinkle-light focus keyline; Periwinkle 14% fallback fill; 2 pt border in Increase Contrast. | `RailButton.updateAppearance` |
| Disabled | 32% view alpha and 48% icon-tint alpha; accessibility enabled state updates. | `RailButton.updateAppearance` |
| Caution / destructive | Dark Ochre is caution; Crimson is destructive. Pair color with icon/text and explicit action wording. | `PlayerBrandColors`; queue footer setup |

The scrubber is a knobless 3 pt top-aligned timeline with a white 15% track and white 72% progress fill; its entire slider frame remains the hit area. Time uses monospaced digits. (`TopAlignedKnoblessSliderCell`; `BottomRailView`.)

Shortcut badges are decorative only: 15 × 13 pt, monospaced, 3 pt radius, white alpha fill/keyline, pointer-transparent, and excluded from accessibility. The parent control supplies the shortcut in its tooltip/accessibility help. (`ShortcutKeyBadge`.)

### Adoption rules

- Use icon-only controls when the glyph is standard and a tooltip/accessibility label can name the action. Use text only for an inherently textual or configurable action.
- Every icon-only custom control must have an AppKit role/action, localized accessibility label, help/tooltip where useful, state/value when applicable, and keyboard-focus presentation.
- Group controls by task (navigation, playback, utility) with adaptive spacing. A sibling may add/remove product-specific controls, but must not add a duplicate control surface.
- Use a native More menu for actions hidden by width/settings; do not duplicate visible actions in it. `BottomRailView.moreTapped` is the current reference.

## 6. Queue Page / panel

The Queue Page is the current right-side in-window panel. It shares the player window and reduces the media width in windowed mode; fullscreen hides it. Its single vertical shared edge is a quiet structural Border/Axis treatment, not a heavy split-view divider. (`PlayerWindowController.layoutPlayerViews`; `QueuePageView.Palette.sharedEdge`.)

### Conceptual panel

```text
┌ Queue ─ [search + sort] [bookmark filter] [close] ┐
├───────────────────────────────────────────────────┤
│ PREVIOUS                                           │
│ rounded item rows                                  │
│ NOW PLAYING                                        │
│ current item + adjacent traversal rows             │
├───────────────────────────────────────────────────┤
│ remove · optional prefix actions · rescan · clear  │
│                                      Total: 00:00  │
└───────────────────────────────────────────────────┘
```

### Header, sections, and footer

- Header: 48 pt dark graphite; 16 pt semibold Periwinkle `Queue` title; search/sort is one 12 pt-radius white-alpha pill with a visual divider; bookmark filter and close are compact symbol controls. The search field is `Search queue`; sort is a native popup action. (`QueuePageView.setupViews`, `layout`.)
- Sections: the projection inserts a `NOW PLAYING` section at the current item; previous-history and section labels are semantic rows, not media items. Preserve section titles during filtering/follow behavior. (`QueueDisplayProjection.sectionedRows`, `followAnchorRow`.)
- Footer: 36 pt graphite footer with a separator above it; destructive remove/clear are explicitly “from queue” and use Crimson; rescan is a quiet white-alpha pill; total duration is right-aligned monospaced 10.5 pt. Controls collapse to the current native More action when space requires it. (`QueuePageView.setupViews`, `layout`.)
- Empty state: faded app icon, light `plus.circle`, 14 pt semibold title, 11.5 pt explanation, and a rounded `Add Media` button. If a filter produces no results, the same surface can offer clear-filter recovery. (`QueuePageView.setupViews`, `updateEmptyState`.)

### Queue-row anatomy

| Element | Current treatment | Transferable requirement |
| --- | --- | --- |
| Row frame | 66 pt table row; content appears as an inset rounded card, not a table grid. | Use an adaptive row height appropriate to sibling metadata, retaining a clear primary/secondary hierarchy. |
| Primary identity | Filename/title, semibold; middle/tail truncation as appropriate. | The sibling chooses its identity field; it remains the strongest row text. |
| Metadata | Duration and file size in smaller secondary/tertiary text. | Replace with sibling-relevant, concise metadata; do not invent irrelevant columns. |
| Current item | Periwinkle 18% fill, Periwinkle outline, solid 4 pt left current bar, white current text. | Keep an explicit non-color-only current-item state. |
| Selected item | White 10% fill and white 28% outline. | Preserve native multiselection semantics plus a visible custom selection state. |
| Hover / press | Subtle white or current-accent overlay; hover outline; press overlay. | Give pointer feedback without obscuring current/selected state. |
| Bookmark / prefix state | Semantic state appears in row information and accessibility; configured-prefix matching prefers the longest matching prefix. | Copy only if the sibling has an equivalent approved state; never use these accents as generic categories. |
| Accessibility | Row role; label is item identity; value conveys now playing, bookmarked, selected, duration, size, or queued. | Expose every visible state semantically, not only by color. |

### Interaction behavior

- Single-click selects and plays the display item; double-click also plays. The table permits multiselection.
- Delete/Backspace removes selected rows from the **queue**, maps visible rows back through the section/filter projection, and retains/reselects the nearest valid row.
- Manual reorder is available only in manual, unfiltered order; it uses local drag/drop and becomes the authoritative order. Search/filter/sort must not confuse visible-row and playback-order indices.
- Context menu is a secondary local shortcut; menus and keyboard paths share semantic action behavior.
- The panel follows current playback only when appropriate. When a user has intentionally scrolled into history, auto-follow is suppressed until they return beyond `NOW PLAYING`; the follow anchor preserves that section label. (`QueuePageView`, `QueueDisplayProjection.followAnchorRow`.)

A sibling may present a queue, timeline, playlist, clips list, or no panel. Keep the header/list/footer hierarchy and native table behaviors only when a comparable user-managed ordered collection exists.

## 7. Settings window

The current Settings window is a 700 × 480 `NSPanel`, minimum 680 × 420, dark Aqua, titled `Settings`, resizable, and independently movable. It stays normal level and is ordered above player windows by ordinary AppKit ordering only while the application is active; it is not globally floating. (`SettingsWindowController.init`, window-key observers.)

The sidebar is a 160 pt visual-effect surface with six current pages in order: Playback, Controls, Queue & Files, Shortcuts, Advanced, and About. Items are 136 × 32 pt, 7 pt rounded, periwinkle selected, and arrow-key navigable. The detail area is a vertically scrolling, flat settings canvas separated by one system separator. (`SettingsWindowController.buildUI`; `SettingsSidebarItemButton`.)

### Reusable settings-page template

```text
Settings window
├ Sidebar: product-relevant pages, text-first, compact selection state
└ Detail scroll view
  ├ Section title (quiet Periwinkle-light)
  ├ Rows: label/control and optional helper
  ├ Section title
  └ Rows …
```

### Reusable settings-row template

| Row part | Current specification |
| --- | --- |
| Section title | 11 pt semibold Periwinkle-light at 88% alpha; 10 pt gap before first row. |
| Label | System body size, 190 pt fixed label column when a label is needed. |
| Control | Native `NSButton`, `NSPopUpButton`, `NSSlider`, or rounded text field; 14 pt after label. |
| Helper | Small system font, secondary label color, word-wrapped to 340 pt; indented under the control (204 pt when labeled, 18 pt when unlabeled). |
| Vertical rhythm | 4 pt label/helper gap; 9 pt row stack spacing; 22 pt between sections; 28/20 pt detail margins. |

### Control selection

- Use a checkbox/toggle for independent boolean behavior.
- Use a popup picker for a bounded set of mutually exclusive values (duration, speed, mode).
- Use a slider with textual value and reset action for a continuous bounded preference.
- Use a rounded text field for validated user-authored text; use monospaced system text when the content is a literal/token.
- Use a button for an immediate action or a destructive/reset action. Pair irreversible actions with clear helper copy and AppKit confirmation when needed.
- Use a segmented control only when a compact mutually exclusive choice needs immediate side-by-side comparison; none is required merely to imitate the reference.

### New-page anti-drift checklist

- Place the page by the sibling app's user task order, not by copied `dwb player` settings names.
- Give the sidebar item a text label, accessibility identifier/label/value, 136 × 32 footprint, focus/hover/pressed/selected states, and arrow-key behavior.
- Build a scrollable detail page using the shared 28/20 margins and section/row rhythm.
- Prefer native controls; ensure each has a concise label, a localized explanatory helper only when useful, and keyboard focus.
- Keep reset/destructive actions in their own semantically named section with scope/reversibility copy.
- Verify long localization, narrow minimum size, Full Keyboard Access, VoiceOver, and increased contrast.

## 8. About page

The current About page is a centered, narrow information stack in Settings—not a separate visual system. It starts with an 88 × 88 app icon beside a leading-aligned identity stack: application name (20 pt semibold), version/build (11.5 pt secondary), and a short product description (12 pt secondary). The header has an 18 pt internal gap. (`SettingsWindowController.buildAboutSection`.)

Below a separator, metadata uses right-aligned 82 pt keys, 12 pt key/value gap, middle-truncated values with tooltips, and 7 pt row spacing. Current metadata is license, supported macOS, interface framework, and playback backend. Links are grouped below the metadata; copyright sits centered at the bottom. The content begins 30 pt from the top, maxes at 420 pt wide, keeps 28 pt minimum side margins, and uses 16 pt stack spacing with intentional 18 pt group gaps. (`SettingsWindowController.buildAboutSection`.)

**Sibling template:** use the sibling icon, name, version/build, one-line purpose, its license/platform/technology facts, approved links, and copyright. Preserve hierarchy, system typography, compact metadata, and centered containment; do not copy `dwb player`'s product claims or backend names.

## 9. Feedback and transient UI

| Surface | Current behavior | Adoption rule |
| --- | --- | --- |
| Playback title | Top-center media overlay with timed dismissal; title is announced through its accessibility label. | Use only for a short content-context announcement; do not make it an input surface. |
| Rename confirmation | Top-center transient material banner, teal primary-prefix role, 2.5 s generation-guarded dismissal, pointer-transparent/non-focusable. | Use a confirmation banner only for an approved sibling action; restart rather than stack rapid updates. |
| Intake recovery | State-driven material card: progress/warning/error icon or spinner, title, message, optional details, explicit recovery buttons, dismiss when allowed. | Explain local recovery and scope; primary action is Periwinkle, status uses semantic colors. |
| Volume HUD | Right side of media area, 82 × up-to-224 pt; 0–100 normal Periwinkle-light, 100–150 secondary orange, ticks at 0/100/150; no input. | Copy only for a comparable continuous adjustment. Keep it state-rendering only. |

All overlay feedback surfaces must avoid capturing pointer events or first responder unless interaction is intrinsically required. `TransientBannerView` and `VolumeBarView` explicitly return no hit-tested view and do not accept first responder. Recovery is the exception: its explicit buttons are interactive and accessible. (`TransientBannerView`, `VolumeBarView`, `IntakeRecoveryView`.)

Use semantic accent differences: Periwinkle for progress/primary recovery, Dark Ochre for warning/error recovery foreground/border in the current surface, teal for primary-prefix rename confirmation, orange only for secondary-prefix/volume-overdrive meaning, and Crimson for destructive actions. Do not create a visually unrelated toast style for new feedback.

## 10. Interaction, accessibility, and responsive behavior

- **Responder chain and keyboard:** menu commands remain the discoverable command surface. Text fields, search, menus, and focused controls take precedence over player shortcuts. Queue Delete/Backspace works only for its table selection; Settings sidebar supports Up/Down navigation. (`AppDelegate`; `QueuePageTableView`; `SettingsSidebarItemButton.keyDown`.)
- **Focus:** custom controls update visible focus state and draw a periwinkle-light keyline. In Increase Contrast the focus border becomes 2 pt. Hidden controls leave key view traversal and accessibility exposure.
- **VoiceOver:** icon-only controls carry labels, help, enabled state, and selected/value state. Queue rows expose current/bookmark/selected/metadata in their value. Decorative shortcut badges, helper icons, and background art are excluded.
- **Pointer states:** hover, pressed, selected/current, and disabled styling is distinct. Color never carries the state alone; symbols, text, selection/current bars, and accessibility values complete the meaning.
- **Motion:** title/rename/volume surfaces reduce or remove animated transition when Reduce Motion is active; the rail's reduced-motion setting avoids scale/slide behavior. Preserve the resulting visible state.
- **Sizing:** use live content bounds. Player minimum size protects the rail; queue width is adaptive with a 260 pt minimum; Settings scrolls rather than clipping content; long titles use middle/tail truncation according to the component.
- **Fullscreen and multiple windows:** fullscreen uses the same window/session and hides Queue Page; each player retains independent queue/playback state. Settings is not a global floating overlay.
- **Localization:** use system text colors/fonts and word wrapping where source does. Do not assume English label width; test long labels, filenames, durations, and assistive technology text.

## 11. Implementation mapping

| Specification area | Principal current source |
| --- | --- |
| Window identity, content hierarchy, fullscreen/windowed layout, title and rename overlays | `dwb/dwb/Player/PlayerWindowController.swift` — `buildWindow`, `layoutPlayerViews`, `showVideoTitleOverlay`, `showRenameConfirmation` |
| Unified playback rail, control state, overflow menu | `dwb/dwb/Player/BottomRailView.swift` — `update`, `moreTapped`; `dwb/dwb/Player/TransportControlsView.swift` — rail visibility/layout |
| Rail buttons, shortcut badge, brand helpers | `dwb/dwb/Player/RailButton.swift` — `RailButton`, `ShortcutKeyBadge`, `PlayerBrandColors`, `PrefixBrandColors` |
| Queue visual system, rows, filtering, footer, empty state, keyboard/drag behavior | `dwb/dwb/Player/QueuePageView.swift` — `QueuePageView`, row/header helper types |
| Queue section/current-item projection and deletion/follow mapping | `dwb/dwb/Player/QueueDisplayProjection.swift` — `sectionedRows`, `followAnchorRow`, `deletionPlan` |
| Recovery and transient banners | `dwb/dwb/Player/IntakeRecoveryView.swift` — `IntakeRecoveryView`, `TransientBannerView`, `TransientBannerStyle` |
| Volume HUD | `dwb/dwb/Player/VolumeBarView.swift` — `VolumeBarView` |
| Settings, About, sidebar and row templates | `dwb/dwb/App/SettingsWindowController.swift` — `buildUI`, `buildSection`, `buildRow`, `buildAboutSection` |
| Preference defaults and setting keys | `dwb/dwb/App/SettingsDefaultsRegistry.swift` |
| Menu/responder command surface | `dwb/dwb/App/AppDelegate.swift` |
| Product identity and app icon registration | `dwb/dwb/Resources/Info.plist`; `dwb/dwb/Resources/Assets.xcassets/AppIcon.appiconset/` |
| Authoritative color system | `assets/Asset_Color_System.md` (authoritative target: `.private/assets/Asset_Color_System.md`) |

## 12. Sibling-app adoption checklist

### Foundations

- [ ] Use the macOS system font, SF Symbols, dynamic system colors, and the authoritative semantic palette.
- [ ] Apply dark graphite surfaces, quiet separators, compact radii, and visible focus states.
- [ ] Keep semantic colors semantic; do not add arbitrary raw colors.

### Player window

- [ ] Use native AppKit window/fullscreen behavior and an unobstructed primary content surface.
- [ ] Provide one coherent edge-aligned playback/control surface appropriate to the sibling app.
- [ ] Adapt panel and content geometry to live bounds; do not copy the video/queue split without product need.

### Controls

- [ ] Use compact icon-first buttons with tooltip, accessibility label/value/help, keyboard focus, and full state styling.
- [ ] Maintain a native More/menu route for width-hidden essential actions.
- [ ] Add only product-required controls and shortcuts.

### Queue or list panel

- [ ] When the sibling has an ordered collection, use header/list/footer hierarchy, clear current/selection states, native scrolling, keyboard behavior, and empty/recovery copy.
- [ ] Map filtered/sectioned visible rows safely to underlying data before mutation.
- [ ] Do not copy local-file rename, rescan, or traversal behavior unless approved for that product.

### Settings

- [ ] Use a compact text-first sidebar and a scrolling, sectioned detail canvas.
- [ ] Preserve the row/template rhythm while substituting sibling-specific pages, labels, and controls.
- [ ] Keep irreversible/reset actions explicit and scoped.

### About

- [ ] Use the reusable icon/identity/metadata/links/copyright hierarchy with sibling facts only.

### Transient feedback

- [ ] Use material-backed, semantic, non-obscuring feedback; restart rapid updates instead of stacking banners.
- [ ] Keep noninteractive overlays pointer-transparent and out of keyboard focus.

### Accessibility and validation

- [ ] Check VoiceOver roles/labels/values/actions, Full Keyboard Access, focus visibility, hover/pressed/disabled/selected/current states, Reduce Motion, Increase Contrast, long text, narrow windows, fullscreen, and multiple windows.
- [ ] Build through the repository wrapper and perform the applicable runtime visual/accessibility pass before shipping UI changes.

## 13. Anti-drift rules

- Do not add arbitrary colors or use status/prefix colors as generic decoration.
- Do not introduce unrelated button shapes, typography, or a custom font.
- Do not add a duplicate playback control surface.
- Do not add sidebar icon clutter unless a product requirement justifies it.
- Do not change the About-page hierarchy into a branded marketing layout.
- Do not create overlays that obscure primary content or capture pointer events unnecessarily.
- Do not copy `dwb player`-specific rename, queue, media, or playback controls into a sibling app without a real product need.
