# Audit Pass Report — `<audit-artifact-stem>`

## 1. Audit Identity

| Field | Value |
|---|---|
| Audit workflow guide version | `v2.4.1` |
| Criteria catalog | `cli_audit_criteria_catalog-v2.4.1.md` |
| Criteria catalog version | `v2.4.1` |
| Campaign ID | `<CAMPAIGN_ID>` |
| Campaign pass | `<PA01–PA06 or bounded audit type>` |
| Audit artifact stem | `<YY-MM-DD_PA0N_pass-slug>` |
| Audited subject | `<path, package, document, or repository>` |
| Governing subject version | `<version or historical version>` |
| Code Agent family | `<Human-selected family>` |
| Model | `<confirmed model>` |
| Effort | `<confirmed effort>` |
| Observed Host version | `<version, unavailable, or not applicable>` |
| Report path | `<campaign-scoped report path>` |
| Metadata path | `<campaign-scoped metadata path>` |
| Criteria state path | `<campaign-scoped criteria path>` |

## 2. Objective and Scope

### Objective

`<one bounded audit objective>`

### In scope

- `<path, section, behavior, or claim>`

### Excluded

- `<excluded item and reason>`

## 3. Generator Handoff Record

- Human instruction: `<source>`
- Owning sources: `<files and versions>`
- Prior Audit artifacts: `<paths or none>`
- Selected claim: `<static, runtime, mixed, release, or re-audit>`
- Approved commands: `<exact list or none>`
- Tool/network/privilege authorization: `<scope or none>`
- Human exceptions: `<records or none>`

## 4. Criteria Selection

- Selected profiles: `<codes or not applicable>`
- Selected modifiers: `<codes or not applicable>`
- Selected criterion IDs: `<IDs>`
- Excluded criterion IDs: `<IDs with reasons>`
- Unresolved applicability or source conflicts: `<items or none>`

## 5. Sources and Evidence

| Evidence ID | Class | Source or command | Version/environment | Preserved location | Limitation |
|---|---|---|---|---|---|
| `<ID>` | `<E-SRC, E-CMD, ...>` | `<reference>` | `<value>` | `<path>` | `<value or none>` |

## 6. Actions Performed

1. `<inspection or approved action>`

## 7. Runtime Commands and Checkpoint Evidence

| Command | Working directory | Approval record | Exit status | Output path |
|---|---|---|---:|---|
| `<exact command or none>` | `<path>` | `<checkpoint record>` | `<status>` | `<path>` |

## 8. Deliverables

| Deliverable | Status | Path | Validation |
|---|---|---|---|
| `<name>` | `<created, updated, unchanged, blocked>` | `<path>` | `<evidence>` |

## 9. Criteria Results

| Criterion ID | Applicability and reason | Evidence status | Result | Linked finding IDs | Severity | Confidence | Exception references | Accepted-risk references | Limitations |
|---|---|---|---|---|---|---|---|---|---|
| `<ID>` | `<applicable, not applicable, or unresolved; reason>` | `<complete, partial, unavailable, or blocked>` | `<Passed, Failed, Not applicable, Not tested, or Blocked>` | `<IDs or none>` | `<value or not applicable>` | `<value or not applicable>` | `<references or none>` | `<references or none>` | `<value or none>` |

### Result Counts

| Result | Count |
|---|---:|
| Passed | `<n>` |
| Failed | `<n>` |
| Not applicable | `<n>` |
| Not tested | `<n>` |
| Blocked | `<n>` |

Coverage and category scores: `<catalog-governed summary or not applicable>`

## 10. Findings Filed or Updated

- `<finding ID> — <one-line title>`
- `None` when no finding was filed or updated.

Finding bodies are maintained only in `audit-findings.md`.

## 11. Items Considered, Not Filed

- `<observation and why it was not filed>`
- `None`

## 12. Limitations and Blockers

- `<limitation, blocked evidence, or open final-acceptance blocker>`
- `None`

## 13. Write-Boundary and Repository-State Verification

| Check | Result | Evidence |
|---|---|---|
| Application source modified | `no / yes / blocked` | `<reference>` |
| Host controls modified | `no / yes / blocked` | `<reference>` |
| Writes confined to authorized Audit scope | `yes / no / blocked` | `<reference>` |
| Pre-existing project dirt preserved | `yes / no / not applicable` | `<reference>` |
| Final project Git state recorded | `yes / no / blocked` | `<reference>` |

## 14. Audit Workflow State

| Item | Status |
|---|---|
| Audit workflow guide version | `v2.4.1` |
| Host instructions present | `yes / no` |
| Host instructions read as optional context | `yes / no / not applicable` |
| audit-metadata-schema.json present | `yes / no` |
| Private-repo mount detected | `yes / no` |
| Prompt saved | `yes / no` |
| Launcher saved | `yes / no` |
| Next audit prompt template | `lean / full / none` |
| Campaign pass | `PA01–PA06` |
| Observed Host maintenance score | `1–5 / unavailable / not applicable` |

## 15. Approval Recommendation and Next Audit Prompt or Remediation Handoff

- Approval recommendation: `<exact recommendation from Criteria Catalog §19>`
- Paired final-acceptance recommendation: `<Block final acceptance or not applicable>`
- Exact approved scope: `<document, artifact, campaign, fixture set, release package, or corrected finding set>`
- Criteria evaluated: `<IDs or criteria-state reference>`
- Open findings by severity: `<counts and IDs>`
- Not tested criteria: `<IDs or none>`
- Blocked criteria: `<IDs or none>`
- Accepted-risk and exception references: `<references or none>`
- Open final-acceptance blockers: `<items or none>`
- Required re-audit: `<scope or none>`
- Human approval status: `<approved, pending, declined, or not applicable>`
- Next action: `<next Audit pass, re-audit, Host remediation proposal, or none>`
- Required inputs: `<artifacts or none>`
- Approval needed: `<checkpoint or Human decision>`
- Suggested scope: `<bounded scope>`

## 16. Audit Pass Execution Snapshot

```yaml
audit_workflow_guide_version: v2.4.1
criteria_catalog_version: v2.4.1
campaign_id: <CAMPAIGN_ID>
campaign_pass: <PA01-PA06-or-bounded-type>
audit_artifact_stem: <artifact-stem>
report_path: <path>
metadata_path: <path>
criteria_state_path: <path>
audit_status: <DOCUMENTATION_ONLY|BUILD_SUCCEEDED|BUILD_FAILED>
audit_post_pass_result: <SUCCEEDED|FAILED|NOT_RUN>
source_files_modified: []
host_controls_modified: []
open_critical: <n>
open_high: <n>
open_medium: <n>
not_tested: <n>
blocked: <n>
next_action: <value>
```
