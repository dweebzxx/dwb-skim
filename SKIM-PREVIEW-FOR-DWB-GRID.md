# Skim Preview — Feature Definition and dwb-grid Implementation Guide

This document describes the **Skim Preview** feature as it exists in `dwb skim`, then
specifies how it should work inside `dwb grid`'s multi-pane model so it can be
implemented (or completed) consistently there.

It is written as a design/reference document. It does not modify code. The `dwb-grid`
tree was read in read-only mode for the "current status" notes in Part 5.

---

## Part 1 — What Skim Preview is (in `dwb skim`)

### 1.1 Concept

Skim Preview is the mechanic that turns a linear media queue into a **fast review
reel**. Instead of playing every queued video from start to finish, the app plays a
short, bounded *preview* of each item and then automatically advances to the next one.
The reviewer watches a continuous stream of representative glimpses and applies review
decisions (rename `keep_` / `delete_`, etc.) without ever manually scrubbing or
skipping.

Skim Preview only shapes **video** playback. Still images and GIFs already have their
own bounded durations (image seconds, GIF loop count); Skim Preview reuses the same
"auto-advance when the budget is spent" completion path for them but does not seek
inside them.

Key properties:

- **Non-destructive and non-seeking-of-intent.** Enabling Skim does not touch the
  currently playing item; it governs the *next* media assignment.
- **Deterministic and testable.** All position/duration math is pure
  (`SkimPreviewPlaybackPlan`, `PreviewRangePlanner`, `ProgressiveRandomSkimPlanner`);
  all timing/lifecycle logic is a pure state machine
  (`SkimPreviewSessionScheduler`, `SkimPlaybackStartIntentCoordinator`). The window
  controller owns only the concrete VLC calls and `DispatchWorkItem` timers.
- **Resilient to VLCKit identity churn.** Logical media ownership is tracked with
  `SkimMediaAssignmentToken` minted by the window, never with `ObjectIdentifier` of
  `VLCMediaPlayer.media`.

### 1.2 User-facing settings

Settings → **Skim Preview** (mirrored into the inline `SkimSettingsStripView` above
the player and the compact markers on the playback rail):

| Setting | Meaning | Default |
|---|---|---|
| **Skim enabled** | Master on/off. Toggled from the rail's Skim button or the app-local double-tap-Option shortcut. | on |
| **Clip duration mode** | `fixed` or `random`. | fixed |
| **Fixed duration** (s) | Preview length when mode is fixed. `0` = play the whole file. | 10 |
| **Random min / max** (s) | Preview length is chosen uniformly in this range per item when mode is random. | 5–15 |
| **Start position** | `beginning` or `random`. | random |
| **Skip intro** (s) | Seconds excluded from the front of every video. Lower bound for both start modes. | 5 |
| **Progressive Random Skim** | Opt-in: replace the single preview with several ordered randomized segments across the whole video (see 1.7). | off |
| **Coverage intensity** | `light` / `standard` / `thorough` — scales Progressive Random Skim's *segment count* only. | standard |
| **Image duration** (s) | Still-image display time. | 3 |
| **GIF loops** | GIF loop count before advance. | 1 |

Numeric fields commit on end-of-editing so a typed value is never rewritten mid-entry.
All settings flow through `SkimSettingsStore` → normalized defaults → a
`.skimPreviewSettingsChanged` / `.playbackSettingsChanged` notification that every open
window and the settings window re-read.

### 1.3 The playback plan (pure math)

`SkimPreviewPlaybackPlan.plan(...)` resolves, from settings + media duration:

- **`startOffsetSeconds`** — where playback should begin:
  - `beginning`: `min(skipIntro, duration - 0.25)`.
  - `random`: lower bound `= min(skipIntro, duration - 0.25)`; upper bound
    `= max(lowerBound, duration - requiredTail)` where `requiredTail` is the clip
    duration (so the full preview still fits) or a `0.25 s` epsilon for full-file.
    A caller-supplied `randomValue ∈ [0,1)` places the start in that window.
  - Unknown/zero media duration → forced to `0` (an intro offset can't be validated
    against an unknown length).
- **`effectiveClipDurationSeconds`** — the preview length, or `nil` for full-file
  ("play to natural end"). Random mode resolves a concrete value up front via
  `resolvedClipDurationSeconds`.

`PreviewRangePlanner.range(...)` converts `(start, previewDuration, totalDuration)`
into an `ActivePreviewRange { startSeconds, endSeconds, totalDurationSeconds }` with
normalized `[0,1]` accessors — this is the model the scrubber highlight draws from.

### 1.4 The session scheduler (pure state machine)

`SkimPreviewSessionScheduler` owns one `SkimPreviewSessionSchedulingState` at a time.
Lifecycle:

1. **`begin`** — a new logical session (`sessionID`, `queueItemID`, planned duration,
   metadata-retry window). Status = `.awaitingReadiness` (or `.ineligible` for
   full-file).
2. **`registerReadiness`** — called when the video is actually playing / a fallback
   timer fires / metadata arrives. Sets `playbackStartUptime = now`,
   `deadlineUptime = now + effectiveDuration`, status `.scheduled`, and returns a
   `SkimPreviewDeadlineUpdate` (`.scheduled` / `.confirmed` / `.replaced` /
   `.suspended` / `.ignored`). If readiness arrives again with a *shorter* refined
   duration it returns `.replaced`.
3. **`claimDeadline`** — the window's timer callback presents the monotonic fire time;
   the scheduler validates generation/tolerance and returns `.fired` or
   `.rejected(reason)`. Only `.fired` authorizes an advance.
4. **`claimNaturalEnd`** — VLC hit EOF before the deadline; races the deadline and
   wins/among terminal states.
5. **`pause` / `resume`** — see 1.6.
6. **`cancel(reason)`** — session abandoned (queue edit, manual nav, skim disabled,
   window closing).

A separate tiny struct, `SkimPreviewDeadlineBinding`, records which
`(sessionID, queueItemID, assignmentToken, generation)` the *pending timer* belongs
to, so a callback that outlived a player rebuild / relocation is recognized as stale
(`SkimDeadlineGuard.mayAdvance`) and can self-heal by rebinding.

### 1.5 The start-intent coordinator (pure state machine)

`SkimPlaybackStartIntentCoordinator` owns the "get VLC to actually start at
`startOffsetSeconds`" handshake, which is unreliable because VLCKit may reset a reused
or fresh player to zero, may not be seekable yet, or may replace its media wrapper:

- `begin` → `bindAssignment` (to a `SkimMediaAssignmentToken`) → `updateMetadata`
  (duration in, desired offset computed via the same `SkimPreviewPlaybackPlan`) →
  `evaluate(observedOffset, isSeekable, isPaused, now)` which returns
  `.requestSeek(offset, attempt, reason)` / `.confirmed` / `.exhausted` / `.stale` /
  `.none(reason)`.
- Bounded retries (default 3) within a retry window; a user scrub sets
  `.userOverridden` and the coordinator stops fighting the user.

### 1.6 Pause / resume semantics (a hard contract)

Pause suspends the **entire window-owned session**: video, image/GIF progression,
Skim+ background audio, the preview deadline, and any pending auto-advance. On
`pause`, `.scheduled` becomes `.suspended` and `suspendedRemainingSeconds` is captured
(`deadline - now`). On `resume`, the deadline is rescheduled as `now + remaining` —
**the preview continues from where it left off, it does not restart.** Navigation
while paused changes the selected item but leaves progress suspended until playback
resumes.

### 1.7 Preview-range relocation (the scrubber)

The playback rail's full-duration scrubber is a `PreviewRangeSlider` that draws the
active preview range as a highlighted band (Dark Teal) with a Periwinkle progress fill
inside it. Dragging it calls `relocatePreviewRange(toNormalizedPosition:)`:

- `PreviewRangePlanner.relocated(...)` recomputes the range preserving the configured
  clip duration;
- the player seeks there, the user-seek is noted (so start-intent yields),
- `SkimPreviewSessionScheduler.replaceDeadlineForRelocation(...)` restarts the
  countdown from the new position (`now + duration`), or, if paused, stores it as the
  new suspended remaining.

### 1.8 Progressive Random Skim (opt-in, `dwb skim` only today)

When enabled, `ProgressiveRandomSkimPlanner.plan(...)` divides the usable timeline
(`duration - skipIntro`) into `count` consecutive buckets and produces `count` ordered,
non-overlapping randomized segments (start + duration per bucket). Count and target
duration are `ln`-growth curves of usable duration (diminishing returns), clamped to
`2…16` segments and `2.5…10 s` each; `light/standard/thorough` scales count by
`0.7 / 1.0 / 1.5`. Each segment is played via the *same* start-intent + scheduler
machinery, one at a time; on deadline the controller advances to the next segment
(`advanceToNextProgressiveRandomSkimSegment`) instead of the next queue item, and only
advances the queue after the last segment. The `→` key manually advances a segment.
The scrubber shows faint tick marks at each segment start.

### 1.9 UI surfaces touched by Skim Preview in `dwb skim`

- **Rail Skim button** — explicit On/Off, shares its action with double-tap-Option;
  Dark-teal-active / muted-inactive styling.
- **`SkimSettingsStripView`** — the collapsible strip above the player (Clip duration
  mode + values, Start position, Skip intro, Image duration, GIF loops, Queue order,
  Loop queue, Progressive skim). Clip-duration and Start-position controls gray out
  (alpha 0.42, disabled) while Skim is off; Skip intro stays live.
- **Compact rail markers** — Clip Duration, Start Position, Skip Intro, Queue Order,
  read-only, spanning the rail between Queue and Fullscreen. Clip Duration / Start
  Position render muted when Skim is off.
- **Scrubber** — preview-range highlight + relocation (1.7), segment ticks (1.8).
- **No** persistent volume slider, replay, 10-second seek, repeat, or standalone
  shuffle controls — deliberately excluded.

---

## Part 2 — `dwb grid` concept (recap)

`dwb grid` is the suite's **multi-pane** player: one window shows 1–4 media containers
("panes") at once (`onePane`, `twoPanes`, `threePanes` asymmetric, `fourPanes` 2×2).
Each pane is an **independent logical playback lane** — its own `VLCMediaPlayer`,
`GridMediaAssignmentRegistry`, `SkimPreviewSessionScheduler`,
`SkimPlaybackStartIntentCoordinator`, position/timer, and pause/lock state — all owned
by a `PanePlayerController` and coordinated by one window-owned
`PlayerWindowController` + `GridSessionState`.

Panes pull media from one shared queue according to a **queue-consumption mode**
(shared sequential, shared shuffle, weighted, allow-duplicates, locked-pane
exclusion). A pane can be **focused** (click / keyboard), **locked** (keeps its media,
does not auto-advance), and **muted**. Global controls express window-wide defaults;
per-pane overrides live in on-pane overlays and a selected-pane inspector.

`dwb grid` keeps the window-level pause/scheduler contract from Part 1.6 and adds
**pane-level** pause and lock.

---

## Part 3 — How Skim Preview maps onto `dwb grid`

The governing principle: **Skim Preview becomes a per-pane concept.** There is no
single "active preview" for the window — there are up to four concurrent preview
sessions, one per visible pane, each with its own scheduler, start intent, deadline
timer, plan context, and `ActivePreviewRange`.

### 3.1 Ownership model

| Concern | Owner in `dwb grid` |
|---|---|
| Preview scheduler state | `PanePlayerController.previewScheduler` (per pane) |
| Start-intent state | `PanePlayerController.playbackStartIntent` (per pane) |
| Assignment tokens | `PanePlayerController.assignmentRegistry` (per pane) |
| Deadline `DispatchWorkItem` + binding | `PanePlayerController.skimPreviewDeadlineWorkItem` / `skimPreviewDeadlineBinding` |
| Readiness fallback `DispatchWorkItem` | `PanePlayerController.skimPreviewReadinessFallbackWorkItem` |
| Plan context (`SkimPreviewPlanContext`) | `PanePlayerController.skimPreviewPlanContext` |
| `ActivePreviewRange` + configured duration | `PanePlayerController.activePreviewRange` / `activePreviewConfiguredDuration` |
| Resolved settings (global + per-pane override) | `GridSessionState.resolveSettings(for:global:globalScaleMode:)` → `ResolvedPaneSettings` |
| Global skim enabled default | `PlayerWindowController.configuredSkimEnabled` |
| Per-pane skim enabled override | `GridSessionState.paneStates[pane].skimEnabledOverride` |

Every pure type from Part 1 is reused **unchanged** except:
`SkimMediaAssignmentToken`/`Registry` is the grid variant (`GridMediaAssignmentToken`
/ `GridMediaAssignmentRegistry`), and `SkimPreviewSessionScheduler` gains
`lock` / `unlock` (3.5). All scheduler/start-intent calls are forwarded through
`PanePlayerController` methods so call sites never reach into the structs directly.

### 3.2 Starting a preview session per pane

When a pane begins video playback (`executePlayCurrentItem` → video path):

1. Resolve the pane's effective settings:
   `let settings = gridSessionState.resolveSettings(for: pane.paneID, global: SkimSettingsStore.shared.snapshot(), globalScaleMode: …)`.
2. If `SkimAssignmentBehavior.nextAssignment(isSkimEnabled: isSkimEnabled(for: pane)) == .skimPreview`,
   call `beginSkimPreviewSession(pane:url:sessionID:reason:)`, which:
   - resolves `plannedDuration` from **that pane's** clip-duration mode/values,
   - builds the pane's `SkimPreviewPlanContext` with the pane's `startMode`,
     `skipIntroSeconds`, `startRandomValue`,
   - calls `pane.beginPlaybackStartIntent(...)` and `pane.beginPreviewScheduling(...)`,
   - if the pane is already paused (global or local), immediately pauses both,
   - schedules a pane-captured readiness fallback `DispatchWorkItem`
     (`[weak readinessPane]`, captured at schedule time so a focus change cannot
     redirect it).
3. Readiness (`applySkimPreviewReadiness(pane:sessionID:playbackURL:source:)`) fires
   from the pane's own `.playing` state change, the fallback timer, or metadata
   arrival. It computes the plan, sets `pane.activePreviewRange`, registers readiness
   with the pane's scheduler, schedules the pane's deadline, and drives the seek via
   the pane's start intent.
4. Deadline fire (`fireSkimPreviewDeadline(pane:…)`) validates generation + binding +
   `pane.claimPreviewDeadline`, then calls the pane-scoped advance
   (`advanceToNextItem`/completion sequence for that pane), or
   `allowPreviewNaturalEndAfterUnadvancableDeadline` if the queue can't advance.

**Session-ID scoping (critical):** each pane increments its **own**
`pane.currentPlaybackSessionID`. Readiness/deadline/relocation must be validated
against the *pane's* session counter, never the window-singular
`currentPlaybackSessionID` (which tracks only the focused pane). See Part 5.1 — this
is the one place the current implementation still mixes the two.

### 3.3 Global vs per-pane "Skim enabled"

- The rail **Skim button** and **double-tap-Option** call
  `toggleSkimEnabled(source:)`, which flips the persisted global
  `SkimSettingsStore.skimEnabled` and then **broadcasts** it:
  `broadcastSkimEnabled` writes `skimEnabledOverride = enabled` into **every unlocked
  pane** in every open window; locked panes keep their prior skim state (mirrors the
  "locked pane exclusion" queue mode — lock preserves *state*, here skim state instead
  of media).
- Every skim call site reads `isSkimEnabled(for: pane)` =
  `paneStates[pane].skimEnabledOverride ?? configuredSkimEnabled`.
- Turning skim **off** for a pane: `cancelSkimPreviewSession(pane:reason:)` cancels
  only that pane's scheduler/start-intent/timers and clears its `activePreviewRange`;
  the pane's current media keeps playing from its current position. Subsequent
  assignments to that pane use full playback until skim is re-enabled.
- Turning skim **on** does not seek or restart any pane's current item; the preserved
  clip-duration/start settings apply to each pane's next assignment.

Per-pane inspector overrides (`PaneInspectorViewController`): clip duration, start
mode, skip intro — stored in `GridSessionState.paneSettings[pane]` as optionals
(`nil` = follow global). These feed `resolveSettings`.

### 3.4 Pause: global vs pane

| Action | Effect on preview scheduling |
|---|---|
| **Global pause** (`setGlobalPause(true)`) | Every pane: `pane.pausePane(now:)` → `previewScheduler.pause` + `playbackStartIntent.pause`, cancel the pane's deadline timer, freeze image/GIF. Each pane captures its own `suspendedRemainingSeconds`. |
| **Global resume** | Every pane resumes; each pane's deadline is rescheduled as `now + itsOwnRemaining`. A pane that was *also* locally paused stays frozen (`isPaneEffectivelyPaused`). |
| **Pane pause** (`pausePane` for one pane) | Only that pane's scheduler/start-intent/timer suspend; siblings keep running their own countdowns. |
| **Pane resume** | Only that pane reschedules from its remaining; if the window is still globally paused it clears `phase` but does not actually resume playback. |

The remaining-duration contract from Part 1.6 is preserved **per pane**.

### 3.5 Lock interaction

`SkimPreviewSessionScheduler` has `lock(sessionID:queueItemID:)` and
`unlock(sessionID:queueItemID:now:)`:

- **Locking a pane** sets `state.isLocked = true`. `claimDeadline` and
  `claimNaturalEnd` then return `.rejected("session-locked")` — the pane keeps its
  current media and does not auto-advance, even though its preview countdown may have
  elapsed.
- **Unlocking** returns a `SkimPreviewDeadlineUpdate`: if the stored deadline is
  already in the past → `.replaced(previous, now)` (advance essentially immediately);
  if still in the future → `.confirmed`; if paused → `.ignored("paused")`; if there
  was no deadline → `.ignored("no-deadline")`. The controller applies that update the
  same way it applies a readiness update.
- Locked panes are also excluded from the skim-enabled broadcast (3.3) and from
  queue-consumption traversal (spec's "locked pane exclusion").

### 3.6 Relocation scoped to the focused pane

The scrubber on the playback rail always represents **the focused pane**
(`paneSnapshot.activePreviewRange`, a `PanePresentationSnapshot` captured for a
specific `paneID` and never re-derived at draw time). `relocatePreviewRange(...)`
therefore acts on `focusedPane()`:

- recompute that pane's `activePreviewRange` via `PreviewRangePlanner.relocated`,
- seek that pane's player, note the user-seek on that pane's start intent,
- `pane.replacePreviewDeadlineForRelocation(...)` restarts that pane's countdown,
- if the focused pane is showing an image, relocation is a no-op.

Non-focused panes have no scrubber; their previews are governed purely by their own
schedulers. (A future enhancement could expose relocation via an on-pane overlay.)

### 3.7 Queue-consumption interaction

Skim Preview is orthogonal to *which* item a pane receives — that is the queue
allocator's job (`requestQueueAssignment(for: paneID)` /
`GridQueueAllocationState`). Skim Preview only governs *how long* the pane shows it
and *where in it* playback starts. When a pane's preview deadline fires, the pane asks
the allocator for its next item under the current consumption mode; the "no duplicates
in the same pass" and weighted-wait rules are unaffected by skim.

Two panes may be assigned the **same** file (allow-duplicates mode, or a small queue).
Each still runs an independent preview session with its own random start offset and
duration — the two panes will typically show different slices of the same video,
which is desirable.

### 3.8 Progressive Random Skim in panes (not yet implemented — see Part 5.3)

`ProgressiveRandomSkimPlanner` is pure and pane-agnostic; it can be adopted per pane
with no change to the planner itself. Recommended scoping:

- Global enable + coverage intensity from Settings → Clip Behavior (Part 4.3), same
  keys as `dwb skim` (`progressiveRandomSkimEnabled`,
  `progressiveRandomSkimIntensity`).
- Each pane plans its own segment list in `applySkimPreviewReadiness` once its media
  duration is known (store on `pane.skimPreviewPlanContext`).
- On deadline: if a later segment exists, `advanceToNextProgressiveRandomSkimSegment`
  within the same pane/session/assignment; else advance the pane's queue item.
- The `→` "next segment" command targets the **focused** pane only.
- Scrubber segment ticks (`PreviewRangeSlider.segmentStarts`) reflect the focused
  pane's segments.
- Because four panes each running up to 16 short segments multiplies timer churn,
  keep the existing "no second timer" approach: drive segment-seek confirmation off
  the shared 0.25 s progress poll, per pane.

---

## Part 4 — Effect on the `dwb grid` UI

### 4.1 Playback rail (bottom, single, shared)

The rail is window-level and always draws for the **focused pane** via
`PanePresentationSnapshot`:

- **Skim button** (`bolt.fill` / `bolt.slash`) — global toggle; `skimActive` /
  `skimInactive` styling; help text "Skim is on/off. Double-tap Option to toggle
  Skim." Reflects `controller.isSkimEnabled` (the global default), not any single
  pane's override.
- **Scrubber** — focused pane's `ActivePreviewRange` band (Dark Teal) + Periwinkle
  progress fill + relocation (3.6); segment ticks when Progressive Random Skim is on.
  Hidden in image mode. Accessibility value: `"Preview range MM:SS to MM:SS"` or
  `"Full media duration"`.
- **Compact markers** — Clip Duration, Start Position, Skip Intro, Queue Order
  (`PlaybackBarPresentation.markers(settings:)`), muted when skim is off. These show
  the **global** values; per-pane overrides are surfaced in the inspector, not here.
- **Pane focus/lock cluster** (right side) — numerals 1–4, focused pane glows
  (Periwinkle), lock glyph per locked pane. A locked pane whose preview has elapsed
  simply stays put — no separate "preview done" indicator is needed.

### 4.2 Per-pane surfaces

- **Focus ring** — Periwinkle 2 px border on the focused pane; dimmer white on
  selected-not-focused; adjacent playing-video panes drop their borders to read as one
  surface. Skim Preview does not change this.
- **On-pane overlay buttons** (hover/focus, hide with chrome) — mute, fit/fill. A
  natural place to later add a per-pane "next segment" / "relocate" affordance, but
  not required for v1.
- **Status overlay** — `Loading… / Empty / Error`. A pane between preview segments or
  mid-advance should **not** flash `Loading…` (the P08.1 race guard already prevents a
  `.loading` regression once `.playingVideo` is shown).
- **Selected-pane inspector** (`slider.horizontal.3` rail button →
  `PaneInspectorViewController` popover) — local overrides for **clip duration, start
  mode, skip intro** for the focused pane. `nil`/empty = follow global. This is the
  per-pane face of Skim Preview settings.

### 4.3 Settings window

Current `dwb grid` sidebar: Playback, **Grid**, **Skim Preview**, Skim+, Controls,
Queue & Files, Shortcuts, Advanced, About. (The end-goal spec renames "Skim Preview"
to **Clip Behavior** and folds image/GIF timing in; either name is fine as long as
the keys stay shared with `SkimSettingsStore`.)

The Skim Preview / Clip Behavior page should carry:

- Clip duration mode (Fixed/Random) + Fixed duration (`0` = full file) + Random
  min/max
- Start position (Beginning/Random)
- Skip intro
- Image duration, GIF loops (may live here or on Playback)
- **Progressive Random Skim** checkbox + **Coverage intensity** (Light/Standard/
  Thorough) — *to add* (Part 5.3)
- Grid page keeps: default pane count, layout preference, pane-selection behavior,
  new-panes-start-locked, multi-pane audio, queue-consumption mode.

No persistent "Skim strip" like `dwb skim`'s `SkimSettingsStripView` — `dwb grid`
deliberately keeps the center stage clean and pushes settings to the window chrome +
inspector.

### 4.4 Shortcuts

- **Double-tap Option** — global skim toggle (app + a grid window active only;
  Option-modified typing/commands untouched).
- **`→`** — next Progressive Random Skim segment, focused pane (when a PRS session is
  active on it).
- Space / `,` / `.` — play-pause / previous / next act on the window session or
  focused pane per the spec's focused-command model.

---

## Part 5 — Current status in the `dwb-grid` repo & remaining work

As of `p10.1 checkpoint`, `dwb grid` already implements most of Part 3:

**Done**
- Per-pane `previewScheduler`, `playbackStartIntent`, `assignmentRegistry`,
  deadline/fallback work items, `skimPreviewPlanContext`, `activePreviewRange` on
  `PanePlayerController`.
- `beginSkimPreviewSession(pane:…)`, `cancelSkimPreviewSession(pane:…)`,
  `applySkimPreviewReadiness(pane:…)`, `scheduleSkimPreviewDeadline(pane:…)`,
  `fireSkimPreviewDeadline(pane:…)`, `relocatePreviewRange` (focused pane).
- Global-default + per-pane `skimEnabledOverride`, `isSkimEnabled(for:)`,
  cross-window `broadcastSkimEnabledGlobally`, locked-pane exclusion from the
  broadcast.
- Scheduler `lock` / `unlock` with deadline-update return; `PanePlayerController`
  `lockPane` / `unlockPane` wired.
- Per-pane pause via `pausePane` / `resumePane`; `GridSessionState`
  `isPaneEffectivelyPaused` distinguishing global vs local.
- `PanePresentationSnapshot` so the rail draws a specific pane without a
  focus-resolution race.
- Rail Skim button, scrubber with preview-range highlight, compact markers, pane
  focus/lock cluster, pane inspector (clip duration / start mode / skip intro
  overrides).
- Shared pure types and their tests carried over
  (`SkimPreviewSessionSchedulerTests`, `SkimPlaybackStartIntentTests`,
  `SkimPreviewPlaybackPlanTests`, `PreviewRangePlannerTests`,
  `PaneSchedulerAssignmentIndependenceTests`,
  `PaneStartIntentDeadlineIndependenceTests`, etc.).

**5.1 Session-ID scoping bug (verify & fix)**
`applySkimPreviewReadiness(pane:…)` still guards with
`sessionID == currentPlaybackSessionID` (window-singular, focused-pane only), while
its `.playing` caller correctly passes `pane.currentPlaybackSessionID`. For a
non-focused pane whose session counter has diverged from the focused pane's, readiness
will bail with `readiness-…-context-mismatch` and the pane will fall back to
natural-end playback instead of honoring its clip duration. The guard should compare
against `pane.currentPlaybackSessionID`. `fireSkimPreviewDeadline` and
`relocatePreviewRange` should be audited for the same mix-up.

**5.2 Unlock deadline application**
Confirm `unlockPane` actually forwards the `SkimPreviewDeadlineUpdate` returned by
`previewScheduler.unlock` into `applySkimPreviewDeadlineUpdate` (schedule/replace a
timer). If it only mutates scheduler state, an unlocked pane whose deadline already
passed will not advance until some other event nudges it.

**5.3 Progressive Random Skim not ported**
`ProgressiveRandomSkimPlanner` / `ProgressiveRandomSkimPlan` and the
`progressiveRandomSkim*` settings keys, the settings UI, the `→` shortcut, the
segment-tick scrubber, and `advanceToNextProgressiveRandomSkimSegment` do **not**
exist in `dwb grid`. Port per Part 3.8 / 4.3 / 4.4. `SkimSettingsSnapshot` in
`dwb grid` would need the two extra fields.

**5.4 Marker / inspector consistency**
Rail markers show global values; the inspector shows per-pane overrides. Decide
whether a focused pane with an active override should visually flag that on the rail
(e.g. marker dot) so the reviewer isn't misled about what the focused pane is doing.

**5.5 Timer-density check**
Four panes × (readiness fallback + deadline) work items, plus up to 16 PRS segments
each, is well within `DispatchQueue.main` capacity, but keep the "no per-segment
NSTimer" rule and lean on the single 0.25 s progress poll for seek confirmation.

---

## Part 6 — Test expectations for the grid implementation

Extend the existing deterministic suite:

- **Pane independence** — two panes, different durations: each fires its own deadline
  at its own time; pausing pane A does not touch pane B's remaining
  (`PaneSchedulerAssignmentIndependenceTests` covers the shape; add duration-divergent
  cases).
- **Session-ID scoping** — a readiness/deadline callback for pane 1 is accepted while
  the focused pane is pane 0 with a different session counter (regression for 5.1).
- **Lock** — locked pane with elapsed deadline does not advance; unlock with a
  past-due deadline produces `.replaced` and the pane advances once.
- **Global vs pane pause** — global pause then global resume reschedules every pane
  from its own remaining; a pane locally paused before a global pause stays frozen
  after global resume.
- **Skim toggle broadcast** — toggling off cancels every unlocked pane's session and
  leaves locked panes' sessions intact; media keeps playing from position.
- **Relocation** — focused pane only; restarts that pane's countdown; no-op on an
  image pane; siblings unaffected.
- **Resolve settings** — per-pane override beats global for clip duration / start
  mode / skip intro; `nil` falls through to global.
- **Progressive Random Skim (when added)** — per-pane segment plans are independent;
  `→` advances only the focused pane; queue advances only after a pane's last segment.

---

## Invariants (apply verbatim to `dwb grid`)

1. Never compare `ObjectIdentifier` of `VLCMediaPlayer.media`. Logical ownership is
   the per-pane `GridMediaAssignmentToken` from `GridMediaAssignmentRegistry`.
2. Preserve `SkimPreviewSessionScheduler`'s `.suspended(remainingSeconds:)` semantics
   — resume continues, never restarts — **per pane**.
3. Keep all playback, preview, start-intent, and background-audio state owned per
   window (and per pane); no shared mutable player/scheduler state.
4. Keep position/duration math in `SkimPreviewPlaybackPlan` /
   `PreviewRangePlanner` / `ProgressiveRandomSkimPlanner` and lifecycle in
   `SkimPreviewSessionScheduler` / `SkimPlaybackStartIntentCoordinator` — pure, no
   VLCKit / UserDefaults / timers. The window controller owns only VLC calls and
   `DispatchWorkItem` timers, captured against a specific pane.
5. Validate every deferred callback against the **owning pane's** session counter and
   the deadline binding generation, not the window-singular focused-pane values.
6. AppKit only; regenerate the Xcode project from `dwb/project.yml`.
