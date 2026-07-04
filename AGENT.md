# AGENT.md — dwb-skim

This file must be read at the start of every AI assistant pass. It records the stable workflow and project constraints for this repository.

---

## Project Identity

- **Name:** dwb-skim
- **Product baseline:** donor copy of `dwb player`, not yet renamed or trimmed into the final skim product
- **Language:** Swift
- **Frameworks:** AppKit, VLCKit via Swift Package Manager
- **Platform:** macOS 13+
- **Workflow guide version:** v6.2
- **AGENT.md authority:** created_by_p01_bootstrap

---

## Build And Package Baseline

- **Canonical build command:** `./scripts/build-app.sh`
- **Canonical package command:** `./scripts/package-release.sh`
- **Canonical installer command:** `./scripts/build-installer.sh`
- **Canonical signing helper:** `./scripts/sign-app.sh`
- **Expected build artifact:** `dist/dwb player.app`
- **Build metadata artifact:** `dist/dwb-player-app-build-info.txt`
- **Project generator:** `dwb/project.yml` via `xcodegen`
- **Xcode project:** `dwb/dwb.xcodeproj`
- **Primary schemes:** `dwb`, `dwbTests`

The current donor copy does not include the `scripts/` build helpers yet. Until a future pass restores or replaces them, treat the README-documented commands as the intended interface and do not invent alternate build entry points inside workflow-only passes.

---

## Source Structure

- `README.md` documents the donor app, release posture, and intended build/package commands.
- `DONOR_MANIFEST.md` describes what was copied into this extracted project and what was intentionally excluded.
- `dwb/project.yml` is the XcodeGen source of truth for targets, versions, bundle IDs, deployment target, and VLCKit dependency.
- `dwb/dwb/` contains the AppKit application code:
  - `App/` for lifecycle, settings, defaults, bookmarks, and debug tooling
  - `Player/` for playback, queue, layout, controls, and media support
  - `Resources/` for `Info.plist` and assets
- `dwb/dwbTests/` contains donor unit tests that currently ship with the extracted copy.
- `docs/images/` contains README screenshots only.

---

## Architecture Rules

- AppKit only. Do not add SwiftUI, storyboards, XIBs, or Interface Builder files unless a future pass explicitly requires them.
- Preserve programmatic UI patterns in the donor codebase.
- Preserve per-window playback ownership; do not introduce shared global playback state across windows without an explicit design pass.
- Keep VLCKit as the playback dependency unless a future pass explicitly scopes dependency changes.
- This repository is presently a donor-derived baseline. Do not assume the app name, bundle IDs, target names, UI copy, or release posture have already been migrated to `dwb-skim`.

---

## Protected Files

- `AGENT.md`
- `metadata-schema.json`
- `scripts/ai-post-pass.zsh`
- `scripts/ai-tool-preflight.zsh`

Only bootstrap or workflow-maintenance passes should modify those files unless a future prompt explicitly says otherwise.

---

## Workflow Rules

- Every pass must run `git status --short` before modifications and again after modifications.
- Every pass must write a markdown report to `build-report-logs/reports/<PASS_ID>-report.md`.
- Every pass must write metadata JSON to `build-report-logs/metadata-reports/<PASS_ID>-metadata.json`.
- Every pass must validate metadata JSON with `python3 -m json.tool`.
- `build-report-logs/` must remain git-ignored.
- `scripts/ai-post-pass.zsh` is the post-pass validator/patcher that launchers invoke automatically after each pass.
- `scripts/ai-tool-preflight.zsh` is the required-tool preflight used by normal launchers before starting the code agent.
- Workflow-only passes must not modify application source files.

---

## Workflow State Requirements

Every pass report must include the fixed ten-row v6.2 workflow table:

| Item | Status |
|---|---|
| Workflow guide version | v6.2 |
| AGENT.md present at project root | yes / no |
| AGENT.md authorized | yes / no |
| metadata-schema.json present at project root | yes / no |
| build-report-logs/ in .gitignore | yes / no |
| Prompt saved for this pass | yes / no |
| Launcher saved for this pass | yes / no |
| Prompt template for next pass | lean (§9) / full (§10) |
| Bootstrap pass needed | yes / no |
| AGENT.md maintenance score | 1–5 |

If the first seven rows are all satisfied after a pass, include the exact sentence:

`Workflow fully initialized. Use lean prompt template for next pass.`

---

## AGENT.md Maintenance Score

Score AGENT.md at the end of every pass:

1. Current and accurate.
2. Minor drift.
3. Moderate drift.
4. Significant drift.
5. Critical drift; implementation should pause until AGENT.md is corrected.

Bootstrap establishes the baseline at score `1`.
