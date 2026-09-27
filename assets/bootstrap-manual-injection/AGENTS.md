# AGENTS.md

## Repository Summary

<One short paragraph or concise bullet list describing the project type, primary stack, build or package system, and repository-specific platform requirements. Do not include a narrative directory tree.>

## Working Directories and Verified Commands

| Purpose | Working directory | Command | Verified on |
|---|---|---|---|
| <purpose> | <project-relative path or `.`> | `<exact command>` | <YYYY-MM-DD / artifact-stem> |

<Add only commands executed successfully during the authorizing or current maintenance pass. Remove this instruction and all unused example rows.>

## Change Boundaries

- <Repository-specific API, schema, generated-code, dependency, lockfile, compatibility, or refactor boundary.>

<Use `- None.` only when the repository has no non-obvious project-specific change boundary. Remove this instruction.>

## Protected Paths and Sensitive Operations

- <Evidence-backed project-specific protected path or sensitive operation.>

<Do not repeat the canonical Host Workflow protected paths. Use `- None.` only when no additional project-specific protection applies. Remove this instruction.>

## Repository-Specific Traps

- <Concrete, recurring, high-cost mistake that is not obvious from source or standard tooling.>

<Use `- None.` when no current repository-specific trap is supported by evidence. Remove this instruction.>

## Verification Expectation

- <Smallest reliable verified command or check required for code-changing passes.>
- <Repository-specific definition-of-done evidence, when applicable.>

<Every command named here must also appear in the verified-command table. Remove this instruction.>

## Temporary Standing Exceptions

- None.

<Replace `- None.` only with temporary entries that each include `Added by`, `Evidence`, and `Remove when`. Remove this instruction.>

## Authorization Record

| Field | Value |
|---|---|
| `agents_md_authority` | <authorized authority enum> |
| Authorizing pass | <artifact-stem> |
| Human authorization date | <YYYY-MM-DD> |
| Workflow version | v2.4.1 |

<!-- BEGIN CANONICAL: MAINTENANCE_SCORE -->
## Maintenance Score

Assign the highest applicable score. The score may hold or increase between passes and may decrease only after a maintenance pass.

1. Current: instructions match observed commands, paths, protections, and declared private workflow controls.
2. Minor drift: one or two non-misleading omissions that do not affect safe execution.
3. Moderate drift: an outdated rule or path, a repeated workaround, or an undeclared private-control candidate. Record at least one drift item; maintenance is recommended.
4. Significant drift: a rule actively misleads, a critical protection is absent, or unresolved placeholders affect work. Record at least one drift item; implementation is blocked.
5. Critical drift: following the instructions could fail a pass, produce incorrect output, or expose private, secret, or user material. Record at least one drift item; implementation is blocked.

Each drift item contains `id`, `severity`, and `summary`.

A successful maintenance pass resolves every drift item in its approved scope, records verification evidence and date, and may reduce the score to the highest level still supported by the remaining evidence. Reset to 1 is permitted only when no unresolved drift remains.
<!-- END CANONICAL: MAINTENANCE_SCORE -->

<!-- BEGIN CANONICAL: PROTECTED_FILES -->
## Protected Files

Implementation passes must not modify Host Workflow controls, including `AGENTS.md`, `CLAUDE.md`, `metadata-schema.json`, `skills-lock.json`, the installed Host report template, `.agents/**`, `.claude/skills`, tool-specific workflow configuration, workflow-owned report and metadata adapters, continuation-state controls, the eight `scripts/cli-*.zsh` paths, or their physical `.dwbskim-private/` targets.

Implementation passes also must not modify `.git/**`, credentials, signing or notarization material, production environment files, secrets, user data, or project-specific protected paths named elsewhere in this document.

Bootstrap, adoption, maintenance, and skill-authorization work may write only the control files named by the active pass contract.

`cli-commit.zsh`, `cli-push.zsh`, and `cli-session-abort.zsh` are Human-invoked only and must never run automatically.
<!-- END CANONICAL: PROTECTED_FILES -->

<!-- BEGIN CANONICAL: WORKFLOW_STATE -->
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
| AGENTS.md maintenance score | 1–5 |
<!-- END CANONICAL: WORKFLOW_STATE -->

<!-- BEGIN CANONICAL: PRIVATE_REPO_WORKFLOW -->
## Private-Repo Workflow

Host Workflow controls live physically under `.dwbskim-private/` and are read through stable project-root adapters.

The project repository must not track those adapters or physical private targets.

Implementation passes do not run Git commands inside `.dwbskim-private/` and do not modify Host Workflow controls.

Bootstrap, adoption, maintenance, and skill-authorization work use an isolated non-protected branch when a repository branch exists, modify only their authorized control scope, and never push.

Commit, push, remote creation, publishing, release, signing, notarization, deployment, and emergency session termination remain separate Human-controlled actions.
<!-- END CANONICAL: PRIVATE_REPO_WORKFLOW -->
