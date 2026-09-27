# Host Pass Report — <artifact-stem>

| Identity Field | Value |
|---|---|
| Pass ID | <P-number or P-number.sub> |
| Pass Name | <concise-pass-name> |
| Pass Type | <implementation / bootstrap / adoption / maintenance / skill_bootstrap> |
| Date | <YYYY-MM-DD> |
| Status | <completed / partial / failed / aborted> |
| Product Result | <succeeded / failed / partial / not-run / unknown> |
| Workflow Finalization Result | <succeeded / failed> |
| Workflow Guide Version | v2.4.1 |
| Code Agent | <agent-family> |
| Model | <confirmed-model> |
| Effort | <confirmed-effort-or-not-applicable> |
| Pass Duration | <duration mirrored from finalized metadata or null> |
| Total Tokens Used | <integer-or-null; restored legacy compatibility value> |
| Verified Total Tokens | <integer-or-null; labelled provider total only> |
| Token Source and Scope | legacy=<cumulative-session / unknown> verified=<cumulative-session / last-request / current-context / unknown> |
| Input Tokens | <integer-or-null> |
| Cached Input Tokens | <integer-or-null> |
| Output Tokens | <integer-or-null> |
| Reasoning Tokens | <integer-or-null> |
| Token Completeness | <complete / partial / unavailable> |
| Session or Conversation ID | <string-or-null> |
| Session Resume Command | <exact-command-or-null> |
| Artifact Stem | <YY-MM-DD_P-number_slug> |
| Project | <project-name> |
| Project Root | <project-relative-or-approved-display-value> |

## Workflow State

| Item | Status |
|---|---|
| Workflow guide version | v2.4.1 |
| AGENTS.md present at project root | yes / no |
| AGENTS.md authorized | yes / no |
| AGENTS.md and CLAUDE.md resolve to one inode in .dwbskim-private/ | yes / no / n/a |
| metadata-schema.json present | yes / no |
| .dwbskim-private/ initialized | yes / no |
| .gitignore covers private workflow controls | yes / no |
| Prompt saved | yes / no |
| Launcher saved | yes / no |
| Next prompt template | lean / full |
| Bootstrap or adoption state | complete / bootstrap needed / adoption needed |
| AGENTS.md maintenance score | 1 / 2 / 3 / 4 / 5 |

## Model Used

- Code Agent: <agent-family>
- Model: <confirmed-model>
- Effort: <confirmed-effort-or-not-applicable>
- Selection source: `cli_model_and_effort_selection_guide-v2.4.1.md`
- Human confirmation: <confirmed-at-or-reference>
- Capability limitation: <None or concise limitation>

## Files Read

- `<project-relative-path>` — <purpose>

## Files Created

- `<project-relative-path>` — <purpose>

## Files Modified

### Pass-produced changes

- `<project-relative-path>` — <change summary>

### Inherited changes remaining

- `<project-relative-path>` — <pre-existing-state summary>

## Implementation Details

<Describe the work performed, important decisions, and resulting behavior.>

## Architectural Constraints Preserved

- <constraint and how it was preserved>

## Verification Performed

| Verification | Command or Method | Result |
|---|---|---|
| <check> | `<command-or-method>` | <passed / failed / unavailable / not applicable> |

## Build Results

- Product/build result: <succeeded / failed / partial / not-run / unknown>
- Workflow finalization result: <succeeded / failed>
- Build or test commands: <commands or None>
- Limitations: <None or explanation>

## Artifacts

### Standard artifacts

- Prompt: `build-report-logs/prompts/<artifact-stem>-prompt.txt`
- Launcher: `build-report-logs/launchers/<artifact-stem>-launcher.zsh`
- Metadata: `build-report-logs/metadata-reports/<artifact-stem>-metadata.json`
- Report: `build-report-logs/reports/<artifact-stem>-report.md`
- Raw log: `build-report-logs/logs/raw-logs/<artifact-stem>-raw.log`
- Clean log: `build-report-logs/logs/clean-logs/<artifact-stem>-clean.log`
- Meta log: `build-report-logs/logs/meta-logs/<artifact-stem>-meta.log`
- Continuation state: `build-report-logs/metadata-reports/<artifact-stem>-continuation-state.json`

### Nonstandard Deliverables

<For each retained deliverable, list `build-report-logs/outputs/<artifact-stem>/<deliverable>` and its description. Write `None.` when there are no nonstandard deliverables.>

## Manual Verification Checklist

<Provide the required Human-verification checklist. Write `- No manual verification required.` when no Human verification remains.>

## Issues Encountered

<Describe each issue, its impact, and its resolution. Write `None.` when no issues were encountered.>

## Unresolved Issues

<Describe each unresolved issue, its impact, and the required next action. Write `None.` when no unresolved issues remain.>

## Recommended Next Prompt

- Recommended action: <next logical pass or no further work>
- Recommended template: <lean / full>
- Objective: <single coherent objective>
- Required context: <finalized artifacts and relevant source paths>
- Constraints: <applicable constraints>
- Suggested model and effort: <reference or confirmed recommendation>

## Pass Execution Snapshot

| Field | Value |
|---|---|
| Pass ID | <P-number or P-number.sub> |
| Artifact Stem | <YY-MM-DD_P-number_slug> |
| Agent Started | <true / false> |
| Capture Process Exit Status | <integer-or-null> |
| Code Agent Exit Status | <integer-or-null> |
| Collector Exit Status | <integer-or-null> |
| Agent Exit Code | <integer-or-null; exact mirror of Code Agent Exit Status> |
| Duration Seconds | <integer-or-null> |
| Total Tokens Used | <integer-or-null; restored legacy compatibility value> |
| Verified Total Tokens | <integer-or-null; labelled provider total only> |
| Legacy Total Scope | <cumulative-session / unknown> |
| Verified Total Scope | <cumulative-session / last-request / current-context / unknown> |
| Token Completeness | <complete / partial / unavailable> |
| Metadata Format Version | <full-provisional-v1 / compact-final-v1> |
| Input Tokens | <integer-or-null> |
| Cached Input Tokens | <integer-or-null> |
| Output Tokens | <integer-or-null> |
| Reasoning Tokens | <integer-or-null> |
| Token Limitations | <comma-separated limitation codes, or none> |
| Session or Conversation ID | <string-or-null> |
| Resume Command | <string-or-null> |
| Product Result | <succeeded / failed / partial / not-run / unknown> |
| Workflow Finalization Result | <succeeded / failed> |
| Metadata Finalized | <true / false> |
| Continuation State Finalized | <true / false> |
| Evidence Index Path | build-report-logs/tmp/<artifact-stem>/runtime/metadata-evidence-index.json |
| Evidence Index SHA-256 | <64 lowercase hexadecimal characters> |

The two totals are distinct values and are never reconciled into one. `Total Tokens Used` is the restored legacy compatibility field; `Verified Total Tokens` is populated only from a labelled provider summary. A pass where they differ, or where one is null and the other is not, is a normal result. Record both exactly as finalized metadata holds them, name any limitation code rather than presenting a bare null, and never estimate or calculate a value the parser did not establish.
