#!/bin/zsh
# CLI Host Workflow Suite v2.4.1 — Human Operator invoked only

set -u
setopt pipefail

readonly CLI_WORKFLOW_VERSION="v2.4.1"
readonly CLI_SCRIPT_NAME="${0:t}"
readonly CLI_STEM_RE='^[0-9]{2}-[0-9]{2}-[0-9]{2}_P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?_[a-z0-9]+(-[a-z0-9]+)*$'
readonly CLI_PASS_ID_RE='^P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?$'

err() { print -u2 -- "ERROR[$CLI_SCRIPT_NAME][$1]: $2"; }
die() { err "$2" "$3"; exit "$1"; }
resolve_dir() { (cd -P -- "$1" 2>/dev/null && pwd -P) || return 1; }
now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

atomic_receipt() {
  local target="$1" content="$2"
  local diagnostics="${target:h}/cli-commit-python-errors.log"
  mkdir -p -- "${target:h}" || die 90 receipt "cannot create receipt directory: ${target:h}"
  python3 -c 'import os,sys,tempfile
path,content=sys.argv[1],sys.argv[2]; directory=os.path.dirname(path) or "."
fd,tmp=tempfile.mkstemp(prefix="."+os.path.basename(path)+".tmp-",dir=directory,text=True)
with os.fdopen(fd,"w",encoding="utf-8") as f:
 f.write(content); f.flush(); os.fsync(f.fileno())
os.replace(tmp,path)' "$target" "$content" 2>>"$diagnostics" || die 90 receipt "cannot atomically write receipt: $target; diagnostics retained at $diagnostics"
}

local root="${AI_PROJECT_ROOT:-}"
local manifest="${AI_COMMIT_MANIFEST_PATH:-}"
local finalized_metadata="${AI_FINALIZED_METADATA_PATH:-}"
local repos=""
local message=""
local stem=""
local project_branch=""
local project_head=""
local private_branch=""
local private_head=""

while (( $# )); do
  case "$1" in
    --project-root) (( $# >= 2 )) || die 2 input "missing value for --project-root"; root="$2"; shift 2;;
    --manifest) (( $# >= 2 )) || die 2 input "missing value for --manifest"; manifest="$2"; shift 2;;
    --finalized-metadata) (( $# >= 2 )) || die 2 input "missing value for --finalized-metadata"; finalized_metadata="$2"; shift 2;;
    --repositories) (( $# >= 2 )) || die 2 input "missing value for --repositories"; repos="$2"; shift 2;;
    --message) (( $# >= 2 )) || die 2 input "missing value for --message"; message="$2"; shift 2;;
    --artifact-stem) (( $# >= 2 )) || die 2 input "missing value for --artifact-stem"; stem="$2"; shift 2;;
    --project-branch) (( $# >= 2 )) || die 2 input "missing value for --project-branch"; project_branch="$2"; shift 2;;
    --project-head) (( $# >= 2 )) || die 2 input "missing value for --project-head"; project_head="$2"; shift 2;;
    --private-branch) (( $# >= 2 )) || die 2 input "missing value for --private-branch"; private_branch="$2"; shift 2;;
    --private-head) (( $# >= 2 )) || die 2 input "missing value for --private-head"; private_head="$2"; shift 2;;
    *) die 2 input "unknown option: $1";;
  esac
done

[[ -n "$root" \
  && -n "$manifest" \
  && -n "$finalized_metadata" \
  && -n "$repos" \
  && -n "$message" \
  && -n "$stem" ]] \
  || die 70 authorization "required: --project-root --manifest --finalized-metadata --repositories project|private|both --message --artifact-stem"

if [[ "$repos" == project || "$repos" == both ]]; then
  [[ -n "$project_branch" && -n "$project_head" ]] \
    || die 70 authorization "project commit requires reviewed --project-branch and --project-head"
fi

if [[ "$repos" == private || "$repos" == both ]]; then
  [[ -n "$private_branch" && -n "$private_head" ]] \
    || die 70 authorization "private commit requires reviewed --private-branch and --private-head"
fi

root="$(resolve_dir "$root")" || die 30 repository "cannot resolve project root"
[[ -f "$manifest" ]] || die 70 manifest "reviewed manifest not found: $manifest"
[[ "$repos" == project || "$repos" == private || "$repos" == both ]] || die 70 authorization "invalid repository selection"
[[ "$stem" =~ $CLI_STEM_RE ]] || die 20 identity "invalid artifact stem: $stem"

local pass_id="${${stem#*_}%%_*}"

[[ "$pass_id" == P<->(|.<->) ]] \
  || die 20 identity "cannot derive a valid Pass ID from artifact stem: $stem"

local commit_message="$pass_id: $message"

[[ -f "$finalized_metadata" ]] \
  || die 70 metadata "finalized metadata not found: $finalized_metadata"

local -a selected
[[ "$repos" == project || "$repos" == both ]] && selected+=("$root")
[[ "$repos" == private || "$repos" == both ]] && selected+=("$root/.dwbskim-private")

local receipt_root="$root/build-report-logs/tmp/$stem/human-actions"
mkdir -p -- "$receipt_root" || die 90 receipt "cannot create receipt directory"

local diagnostics="$receipt_root/cli-commit-python-errors.log"
local allowed_changes="$receipt_root/.allowed-pass-produced-paths.tsv"

python3 -c 'import json,os,sys
metadata=json.load(open(sys.argv[1],encoding="utf-8"))

if metadata.get("workflow_version")!="v2.4.1":
 raise SystemExit("metadata workflow version is not v2.4.1")
if metadata.get("artifact_stem")!=sys.argv[2]:
 raise SystemExit("metadata artifact stem does not match")
if metadata.get("workflow_finalization_result")!="succeeded":
 raise SystemExit("workflow finalization did not succeed")
if metadata.get("metadata_finalized") is not True:
 raise SystemExit("metadata is not finalized")
if metadata.get("continuation_state_finalized") is not True:
 raise SystemExit("continuation state is not finalized")

rows=[]
for change in metadata.get("pass_produced_changes") or []:
 repo=change.get("repository")
 path=change.get("path")
 if repo not in ("project","private") or not isinstance(path,str) or not path:
  continue
 rows.append((repo,path))

with open(sys.argv[3],"w",encoding="utf-8") as f:
 for repo,path in sorted(set(rows)):
  f.write(repo+"\t"+path+"\n")
 f.flush()
 os.fsync(f.fileno())' \
  "$finalized_metadata" \
  "$stem" \
  "$allowed_changes" \
  2>>"$diagnostics" \
  || die 70 metadata "finalized metadata does not authorize this commit; diagnostics retained at $diagnostics"

local repo

# Phase one: validate every selected repository before creating any commit.
for repo in "${selected[@]}"; do
  [[ -d "$repo/.git" ]] \
    || die 30 repository "selected repository unavailable: $repo"

  local label=project
  [[ "$repo" == "$root/.dwbskim-private" ]] && label=private

  local expected_branch="$project_branch"
  local expected_head="$project_head"

  if [[ "$label" == private ]]; then
    expected_branch="$private_branch"
    expected_head="$private_head"
  fi

  local actual_branch actual_head
  actual_branch="$(git -C "$repo" branch --show-current 2>/dev/null)" \
    || die 30 repository "cannot read current branch: $label"
  actual_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" \
    || die 30 repository "cannot read current commit: $label"

  [[ "$actual_branch" == "$expected_branch" ]] \
    || die 30 identity "$label branch changed after review: expected $expected_branch; found $actual_branch"

  [[ "$actual_head" == "$expected_head" ]] \
    || die 30 identity "$label HEAD changed after review: expected $expected_head; found $actual_head"

  git -C "$repo" diff --cached --quiet -- \
    || die 70 repository-state "$label repository has pre-existing staged changes; review and resolve them before using cli-commit.zsh"

  local validated_paths="$receipt_root/.validated-$label.paths"
  : > "$validated_paths" \
    || die 90 manifest "cannot create validated path record: $validated_paths"

  while IFS=$'\t' read -r manifest_repo manifest_path \
    || [[ -n "$manifest_repo$manifest_path" ]]; do
    [[ -z "$manifest_repo" || "$manifest_repo" == \#* ]] && continue
    [[ "$manifest_repo" == "$label" ]] || continue
    [[ -n "$manifest_path" ]] \
      || die 70 manifest "empty manifest path for repository: $label"

    local normalized
    normalized="$(python3 -c 'import os,sys
repo=os.path.realpath(sys.argv[1])
raw=sys.argv[2]

if os.path.isabs(raw):
 raise SystemExit("absolute manifest path")
path=os.path.normpath(raw.replace("\\","/"))
if path in ("",".","..") or path.startswith("../"):
 raise SystemExit("manifest path escapes repository")

resolved=os.path.realpath(os.path.join(repo,path))
if os.path.commonpath([repo,resolved])!=repo:
 raise SystemExit("manifest path resolves outside repository")

print(path)' "$repo" "$manifest_path" 2>>"$diagnostics")" \
      || die 70 manifest "manifest path escapes selected repository or is malformed: $manifest_path; diagnostics retained at $diagnostics"

    [[ "$normalized" != ".DS_Store" && "$normalized" != */.DS_Store ]] \
      || die 70 manifest ".DS_Store must not be committed: $normalized"

    [[ ! -d "$repo/$normalized" ]] \
      || die 70 manifest "commit manifest entries must name individual files, not directories: $normalized; list each pass-produced file beneath it"

    grep -Fqx -- "$label"$'\t'"$normalized" "$allowed_changes" \
      || die 70 manifest "manifest path is not a finalized pass-produced change: $label:$normalized"

    print -r -- "$normalized" >> "$validated_paths" \
      || die 90 manifest "cannot record validated manifest path: $normalized"
  done < "$manifest"

  [[ -s "$validated_paths" ]] \
    || die 70 manifest "no reviewed pass-produced paths for repository: $label"

  LC_ALL=C sort -u "$validated_paths" -o "$validated_paths" \
    || die 90 manifest "cannot normalize validated manifest paths: $validated_paths"
done

print -- "Reviewed pass-local commit plan:"

for repo in "${selected[@]}"; do
  local label=project
  [[ "$repo" == "$root/.dwbskim-private" ]] && label=private

  local validated_paths="$receipt_root/.validated-$label.paths"

  print -- "$label repository:"

  while IFS= read -r planned_path || [[ -n "$planned_path" ]]; do
    [[ -n "$planned_path" ]] && print -- "  $planned_path"
  done < "$validated_paths"
done

local -a committed_log

# Recovery for a partially completed multi-repository commit. A local commit is
# fully reversible, so record the exact reversal rather than leaving the operator
# to discover the half-committed state on their own.
partial_die() {
  local code="$1" rule="$2" message="$3"
  if (( ${#committed_log} )); then
    local body entry done_label done_repo done_head
    body="status=partial
timestamp=$(now)
artifact_stem=$stem
failed_repository=$label
failure_rule=$rule
failure_summary=$message
"
    for entry in "${committed_log[@]}"; do
      IFS=$'\t' read -r done_label done_repo done_head <<< "$entry"
      body+="committed_repository=$done_label
undo_$done_label=git -C $done_repo reset --soft $done_head
"
    done
    atomic_receipt "$receipt_root/partial-commit.recovery" "$body"
    err partial-commit "a prior repository already committed; reversal instructions written to ${receipt_root#$root/}/partial-commit.recovery"
  fi
  die "$code" "$rule" "$message"
}

# Phase two: create the requested commits only after all deterministic
# repository, identity, metadata, and manifest checks have passed.
for repo in "${selected[@]}"; do
  local label=project
  [[ "$repo" == "$root/.dwbskim-private" ]] && label=private

  local expected_branch="$project_branch"
  local expected_head="$project_head"

  if [[ "$label" == private ]]; then
    expected_branch="$private_branch"
    expected_head="$private_head"
  fi

  local actual_branch actual_head
  actual_branch="$(git -C "$repo" branch --show-current 2>/dev/null)" \
    || partial_die 30 repository "cannot re-read current branch: $label"
  actual_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" \
    || partial_die 30 repository "cannot re-read current commit: $label"

  [[ "$actual_branch" == "$expected_branch" && "$actual_head" == "$expected_head" ]] \
    || partial_die 30 identity "$label repository changed after commit preflight"

  local validated_paths="$receipt_root/.validated-$label.paths"
  local -a paths
  paths=("${(@f)$(<"$validated_paths")}")
  paths=("${(@)paths:#}")

  git -C "$repo" add -- "${paths[@]}" || {
    git -C "$repo" restore --staged -- "${paths[@]}" >/dev/null 2>&1 || true
    partial_die 30 staging "scoped staging failed for repository: $label"
  }

  local staged_paths="$receipt_root/.staged-$label.paths"
  git -C "$repo" -c core.quotepath=false diff --cached --name-only -- \
    > "$staged_paths" \
    || {
      git -C "$repo" restore --staged -- "${paths[@]}" >/dev/null 2>&1 || true
      partial_die 90 staging "cannot inspect scoped staging for repository: $label"
    }

  LC_ALL=C sort -u "$staged_paths" -o "$staged_paths" \
    || {
      git -C "$repo" restore --staged -- "${paths[@]}" >/dev/null 2>&1 || true
      partial_die 90 staging "cannot normalize staged path list for repository: $label"
    }

  cmp -s "$validated_paths" "$staged_paths" || {
    git -C "$repo" restore --staged -- "${paths[@]}" >/dev/null 2>&1 || true
    partial_die 30 staging "staged paths differ from the reviewed finalized pass-local manifest: $label"
  }

  git -C "$repo" commit -m "$commit_message" -- || {
    git -C "$repo" restore --staged -- "${paths[@]}" >/dev/null 2>&1 || true
    partial_die 30 commit "commit failed for repository: $label"
  }

  committed_log+=("$label"$'\t'"$repo"$'\t'"$expected_head")

  local committed_branch committed_head receipt_content
  committed_branch="$(git -C "$repo" branch --show-current 2>/dev/null)" \
    || die 90 receipt "cannot read committed branch: $label"
  committed_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" \
    || die 90 receipt "cannot read committed identity: $label"

  receipt_content="$(
    printf \
      'workflow_version=v2.4.1\ntimestamp=%s\nartifact_stem=%s\nrepository=%s\nreviewed_branch=%s\nreviewed_head=%s\ncommitted_branch=%s\ncommit=%s\nmessage=%s\npaths=%s\n' \
      "$(now)" \
      "$stem" \
      "$label" \
      "$expected_branch" \
      "$expected_head" \
      "$committed_branch" \
      "$committed_head" \
      "$commit_message" \
      "${(j:,:)paths}"
  )"

  atomic_receipt "$receipt_root/commit-$label.receipt" "$receipt_content"
done

print -- "Scoped commit completed for: $repos"
