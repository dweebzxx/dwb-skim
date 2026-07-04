# AGENT.md — dwb-skim

This file must be read at the start of every AI assistant pass. It records the stable workflow and project constraints for this repository.

---

## Project Identity

- **Name:** dwb-skim
- **Product baseline:** renamed donor-derived baseline for `dwb - skim`; skim-specific behavior and trimming remain future work
- **Language:** Swift
- **Frameworks:** AppKit, VLCKit via Swift Package Manager
- **Platform:** macOS 13+
- **Workflow guide version:** v6.2
- **AGENT.md authority:** created_by_p01_bootstrap

---

## Build And Package Baseline

- **Canonical build command:** `xcodebuild -project dwb/dwb-skim.xcodeproj -scheme dwb-skim -configuration Debug -destination 'platform=macOS' build`
- **Canonical package command:** none currently present; future packaging pass must define the package interface before use
- **Canonical installer command:** none currently present; future installer/release pass must define the installer interface before use
- **Canonical signing helper:** none currently present; signing/notarization remain out of scope unless explicitly requested
- **Expected debug build artifact:** DerivedData app bundle named `dwb - skim.app` produced by the canonical xcodebuild command
- **Build metadata artifact:** none currently present
- **Project generator:** `dwb/project.yml` via `xcodegen`
- **Xcode project:** `dwb/dwb-skim.xcodeproj`
- **Primary schemes:** `dwb-skim`, `dwb-skimTests`

Current build identity after P02:
- App target/scheme: `dwb-skim`
- Test target/scheme: `dwb-skimTests`
- Public product/app bundle name: `dwb - skim.app`
- App bundle identifier: `com.dwb.skim`
- Test bundle identifier: `com.dwb.skimTests`
- Swift module names: `dwb_skim`, `dwb_skimTests`

The donor build/package/signing helper scripts are absent. Use the canonical direct xcodebuild command above for current build verification. A future packaging/release pass may add dedicated helper scripts, but workflow-only passes must not invent or install tooling.

---

## Source Structure

- `README.md` documents the current `dwb - skim` app identity, local build/test commands, feature scope, and remaining work.
- `DONOR_MANIFEST.md` preserves donor provenance and notes which extraction/rename work has been completed.
- `dwb/project.yml` is the XcodeGen source of truth for targets, versions, bundle IDs, deployment target, and VLCKit dependency.
- `dwb/dwb-skim/` contains the AppKit application code:
  - `App/` for lifecycle, settings, defaults, bookmarks, and debug tooling
  - `Player/` for playback, queue, layout, controls, and media support
  - `Resources/` for `Info.plist` and assets
- `dwb/dwb-skimTests/` contains the unit tests for the renamed app.
- `docs/images/` contains README screenshots only.

---

## Architecture Rules

- AppKit only. Do not add SwiftUI, storyboards, XIBs, or Interface Builder files unless a future pass explicitly requires them.
- Preserve programmatic UI patterns in the donor codebase.
- Preserve per-window playback ownership; do not introduce shared global playback state across windows without an explicit design pass.
- Keep VLCKit as the playback dependency unless a future pass explicitly scopes dependency changes.
- This repository is a renamed donor-derived baseline. The app name, bundle IDs, target names, schemes, public strings, and documentation were migrated in P02; skim-specific behavior, trimming, packaging, signing, and release posture still require future passes.

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
