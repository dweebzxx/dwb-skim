# dwb - skim Donor Manifest

## Purpose

`donor-dwb-skim` is a curated copy of reusable `dwb player` project material for a future extracted `dwb - skim` project.

This is not a finished `dwb - skim` app. It has not been renamed, bootstrapped, trimmed, or changed for short-clip skimming behavior. Copied files are expected to still reference `dwb player` until a later extraction/bootstrap pass handles adoption and rename work.

Before using this as its own project, manually move `donor-dwb-skim` out of the `dwb-player` repository and treat the moved folder as the new project root.

No user media files were copied or mutated.

## Included Paths

- `.gitignore` - reusable ignore baseline for Xcode build output, local state, logs, packages, and environment files.
- `LICENSE` - source license context for the copied app source.
- `README.md` - current project overview, feature inventory, build notes, and app behavior context.
- `docs/images/` - public README images that document the current player, queue, settings, and multi-window UI.
- `dwb/project.yml` - XcodeGen project specification with app/test targets, versions, Info.plist path, and VLCKit SPM dependency.
- `dwb/dwb.xcodeproj/project.pbxproj` - current Xcode project structure and build settings for source readability after extraction.
- `dwb/dwb.xcodeproj/project.xcworkspace/contents.xcworkspacedata` - workspace metadata required by the copied Xcode project.
- `dwb/dwb.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` - pinned VLCKit SwiftPM dependency resolution.
- `dwb/dwb.xcodeproj/xcshareddata/xcschemes/dwb.xcscheme` - shared app build scheme.
- `dwb/dwb.xcodeproj/xcshareddata/xcschemes/dwbTests.xcscheme` - shared test scheme useful for future donor validation.
- `dwb/dwb/App/` - AppKit entry point, app delegate, menus, settings, defaults, bookmark store, debug console, and log sanitizer.
- `dwb/dwb/Player/` - VLCKit playback integration, per-window controller, queue model/UI, playback completion policy, media support, image/GIF handling, transport controls, bottom rail, rail buttons, volume UI, scale mode, fullscreen/window layout, and file operation code.
- `dwb/dwb/Resources/` - app Info.plist and non-generated app icon asset catalog.
- `dwb/dwbTests/` - focused tests for reusable model/helper behavior including media support, prefix rename planning, queue projection, settings defaults, bookmarks, debug sanitizing, and completion policy.

## Excluded Paths

- `AGENT.md` - local workflow policy, not reusable app/project source.
- `metadata-schema.json` - local AI pass metadata schema, not donor app source.
- `scripts/` - local build, packaging, signing, testing, and AI workflow scripts; future project should bootstrap its own workflow.
- `build-report-logs/` - local AI prompts, launchers, raw logs, clean logs, meta logs, reports, and metadata reports.
- `.git/` - repository history and Git internals.
- `.github/workflows/` - current repository CI workflow, not part of the donor app package.
- `docs/SIGNING.md` - useful release posture context, but excluded because the required donor safety scan rejects any copied path containing `signing`.
- `dist/` - generated app bundle and local build metadata.
- `.tmp/`, `DerivedData/`, `.build/`, `node_modules/` - generated build/dependency/cache output.
- `dwb/dwb.xcodeproj/**/xcuserdata/` - user-specific Xcode state.
- `assets/` - local prompt/publish/design assets outside the app resource bundle.
- `audit/` - local audit and workflow artifacts.
- `.env`, `.env.*`, and secret/token/credential/keychain/provisioning/certificate/notarization/signing material - private or release-sensitive local files.
- `.DS_Store`, raw logs, clean logs, meta logs, launcher files, prompt files, report files, and metadata report files - generated or local-only workflow noise.
- User media files - not app source and not needed for donor extraction.

## Follow-Up Work After Extraction

- Bootstrap the new extracted project workflow.
- Rename the app, project, targets, bundle IDs, schemes, product names, public strings, and documentation from `dwb player` to `dwb - skim`.
- Trim normal long-form playback behavior that does not belong in the skim app.
- Add the configured short-clip playback/skimming model.
- Review settings and defaults for the new product scope.
- Update README, license notes, About copy, signing notes, and release/build documentation for the extracted project.
