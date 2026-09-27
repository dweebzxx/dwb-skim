#!/bin/zsh
# CLI Host Workflow Suite v2.4.1

set -u
setopt pipefail

readonly CLI_WORKFLOW_VERSION="v2.4.1"
readonly CLI_SCRIPT_NAME="${0:t}"
readonly CLI_STEM_RE='^[0-9]{2}-[0-9]{2}-[0-9]{2}_P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?_[a-z0-9]+(-[a-z0-9]+)*$'
readonly CLI_PASS_ID_RE='^P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?$'

err() { print -u2 -- "ERROR[$CLI_SCRIPT_NAME][$1]: $2"; }
warn() { print -u2 -- "WARNING[$CLI_SCRIPT_NAME][$1]: $2"; }
die() { local c="$1" s="$2" m="$3"; err "$s" "$m"; exit "$c"; }
need() { local n="$1"; [[ -n "${(P)n:-}" ]] || die 2 input "missing environment variable: $n"; }
resolve_dir() { (cd -P -- "$1" 2>/dev/null && pwd -P) || return 1; }
inside() { [[ "$1" == "$2" || "$1" == "$2"/* ]] || die 20 path "path escapes permitted root: $1"; }
now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

check_auto() {
  local n
  for n in AI_WORKFLOW_VERSION AI_PROJECT_ROOT AI_REPORT_ROOT AI_PASS_ID AI_ARTIFACT_STEM AI_PASS_TYPE AI_SCRIPTS_MODEL AI_RUNTIME_STATE_PATH AI_META_LOG_PATH; do need "$n"; done
  [[ "$AI_WORKFLOW_VERSION" == "$CLI_WORKFLOW_VERSION" ]] || die 2 version "expected $CLI_WORKFLOW_VERSION; received $AI_WORKFLOW_VERSION"
  local r
  r="$(resolve_dir "$AI_PROJECT_ROOT")" || die 20 project-root "cannot resolve project root: $AI_PROJECT_ROOT"
  [[ "$r" == "$AI_PROJECT_ROOT" ]] || die 20 project-root "AI_PROJECT_ROOT must be resolved: $r"
  [[ "$AI_REPORT_ROOT" == "$AI_PROJECT_ROOT/build-report-logs" ]] || die 20 path "AI_REPORT_ROOT must equal $AI_PROJECT_ROOT/build-report-logs"
  [[ "$AI_PASS_ID" =~ $CLI_PASS_ID_RE ]] || die 20 identity "invalid pass ID: $AI_PASS_ID"
  [[ "$AI_ARTIFACT_STEM" =~ $CLI_STEM_RE ]] || die 20 identity "invalid artifact stem: $AI_ARTIFACT_STEM"
  [[ "$AI_SCRIPTS_MODEL" == whole-directory || "$AI_SCRIPTS_MODEL" == per-file ]] || die 2 scripts-model "invalid scripts model: $AI_SCRIPTS_MODEL"
  inside "$AI_RUNTIME_STATE_PATH" "$AI_REPORT_ROOT"
  inside "$AI_META_LOG_PATH" "$AI_REPORT_ROOT"
}

json_merge() {
  local target="$1" patch="$2"
  local diagnostics="${target:h}/cli-initialize-python-errors.log"
  mkdir -p -- "${target:h}" || die 90 state "cannot create state parent: ${target:h}"
  python3 -c 'import json,os,sys,tempfile
p=sys.argv[1]; patch=json.loads(sys.argv[2]); data={}
if os.path.exists(p):
 data=json.load(open(p,encoding="utf-8"))
 if not isinstance(data,dict): raise SystemExit("existing JSON root is not an object")
data.update(patch); d=os.path.dirname(p) or "."
fd,tmp=tempfile.mkstemp(prefix=".tmp-",dir=d,text=True)
with os.fdopen(fd,"w",encoding="utf-8") as f:
 json.dump(data,f,indent=2,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno())
os.replace(tmp,p)' "$target" "$patch" 2>>"$diagnostics" || die 90 state "atomic JSON update failed: $target; diagnostics retained at $diagnostics"
}

check_auto
for n in AI_CODE_AGENT AI_REPORT_TEMPLATE AI_METADATA_SCHEMA; do need "$n"; done

local -a blockers tools
local seed_mode_active=false
[[ "$AI_PASS_TYPE" == bootstrap || "$AI_PASS_TYPE" == adoption ]] && seed_mode_active=true

[[ "$(uname -s 2>/dev/null)" == Darwin ]] || blockers+=("platform must be macOS")
[[ "$(uname -m 2>/dev/null)" == arm64 ]] || blockers+=("machine architecture must be arm64")
[[ -d "$AI_PROJECT_ROOT/.git" || "$AI_PASS_TYPE" == bootstrap || "$AI_PASS_TYPE" == adoption ]] || blockers+=("project Git repository is missing")
[[ -d "$AI_PROJECT_ROOT/.dwbskim-private" || "$AI_PASS_TYPE" == bootstrap || "$AI_PASS_TYPE" == adoption ]] || blockers+=("private workflow root is missing")

if [[ "$AI_PASS_TYPE" != bootstrap && "$AI_PASS_TYPE" != adoption ]]; then
  [[ -L "$AI_PROJECT_ROOT/AGENTS.md" ]] || blockers+=("AGENTS.md is not a symlink")
  [[ -L "$AI_PROJECT_ROOT/CLAUDE.md" ]] || blockers+=("CLAUDE.md is not a symlink")
  if [[ -L "$AI_PROJECT_ROOT/AGENTS.md" && -L "$AI_PROJECT_ROOT/CLAUDE.md" ]]; then
    local a c p
    a="$(stat -L -f '%d:%i' "$AI_PROJECT_ROOT/AGENTS.md" 2>/dev/null)"
    c="$(stat -L -f '%d:%i' "$AI_PROJECT_ROOT/CLAUDE.md" 2>/dev/null)"
    p="$(stat -L -f '%d:%i' "$AI_PROJECT_ROOT/.dwbskim-private/AGENTS.md" 2>/dev/null)"
    [[ -n "$a" && "$a" == "$c" ]] || blockers+=("AGENTS.md and CLAUDE.md do not resolve to one inode")
    [[ -n "$p" && "$a" == "$p" ]] || blockers+=("AGENTS.md and CLAUDE.md do not resolve to .dwbskim-private/AGENTS.md")
  fi
fi

[[ -f "$AI_REPORT_TEMPLATE" ]] || blockers+=("Host report template is missing: $AI_REPORT_TEMPLATE")
[[ "$AI_REPORT_TEMPLATE" == "$AI_PROJECT_ROOT/.dwbskim-private/workflow-templates/pass-report-template.md" ]] || blockers+=("Host report template path must be .dwbskim-private/workflow-templates/pass-report-template.md")
[[ -f "$AI_METADATA_SCHEMA" ]] || blockers+=("metadata schema is missing: $AI_METADATA_SCHEMA")

if [[ "$seed_mode_active" == true ]]; then
  [[ -x "$AI_PROJECT_ROOT/.dwbskim-private/scripts/$CLI_SCRIPT_NAME" ]] || blockers+=("seeded private script is missing or not executable: .dwbskim-private/scripts/$CLI_SCRIPT_NAME")
else
  [[ -x "$AI_PROJECT_ROOT/scripts/$CLI_SCRIPT_NAME" ]] || blockers+=("stable root script is missing or not executable: scripts/$CLI_SCRIPT_NAME")
fi

# ---------------------------------------------------------------------------
# Installed engine set (Host Guide 2.3, 15.1).
#
# A pass may not begin on a partially installed or mixed-version engine. The
# three outcomes are distinguished deliberately, because the corrective action
# differs: a partial installation is completed, a mixed-version installation is
# refused, and an authorized seed-mode pass inspects the physical .dwbskim-private/
# destinations before root adapters exist.
#
# No tool is executed here. Presence and readability only; the parser, the
# status checker, and both fixture catalogs are invoked elsewhere or not at all.
# ---------------------------------------------------------------------------

local -a engine_missing engine_mixed
local -a engine_scripts engine_tools
engine_scripts=(
  cli-initialize.zsh cli-pre-pass.zsh cli-agent-runner.zsh cli-post-pass.zsh
  cli-log-collector.zsh cli-commit.zsh cli-push.zsh cli-session-abort.zsh
)
engine_tools=(
  invocation_contract_check-v2.4.1.py
  provider_telemetry_extract-v2.4.1.py
  provider_telemetry_fixtures-v2.4.1.json
  metadata_contract_fixtures-v2.4.1.json
  capture_status_contract_check-v2.4.1.py
)

check_engine_member() {
  local physical="$1" adapter="$2" label="$3"
  if [[ -f "$physical" ]]; then
    if [[ "$seed_mode_active" != true && -n "$adapter" && ! -e "$adapter" ]]; then
      engine_missing+=("$label is installed but its stable root path is absent: ${adapter#$AI_PROJECT_ROOT/}")
    fi
    return 0
  fi
  engine_missing+=("$label is absent: ${physical#$AI_PROJECT_ROOT/}")
  return 1
}

local engine_name
for engine_name in $engine_scripts; do
  check_engine_member \
    "$AI_PROJECT_ROOT/.dwbskim-private/scripts/$engine_name" \
    "$AI_PROJECT_ROOT/scripts/$engine_name" \
    "canonical Host script $engine_name" || continue
  # A script that declares a different workflow version makes the installation
  # mixed rather than merely stale.
  grep -q 'CLI_WORKFLOW_VERSION="v2.4.1"' "$AI_PROJECT_ROOT/.dwbskim-private/scripts/$engine_name" 2>/dev/null \
    || engine_mixed+=("installed script does not declare v2.4.1: .dwbskim-private/scripts/$engine_name")
done

for engine_name in $engine_tools; do
  check_engine_member \
    "$AI_PROJECT_ROOT/.dwbskim-private/tools/$engine_name" \
    "$AI_PROJECT_ROOT/tools/$engine_name" \
    "governed tool $engine_name" || continue
  [[ -r "$AI_PROJECT_ROOT/.dwbskim-private/tools/$engine_name" ]] \
    || engine_missing+=("governed tool is not readable: .dwbskim-private/tools/$engine_name")
done

if (( ${#engine_mixed} )); then
  local mixed_entry
  for mixed_entry in $engine_mixed; do
    blockers+=("mixed-version engine asset: $mixed_entry; a mixed installation is refused rather than completed")
  done
elif (( ${#engine_missing} )); then
  local missing_entry
  for missing_entry in $engine_missing; do
    blockers+=("incomplete engine installation: $missing_entry")
  done
fi

if [[ -n "${AI_RUNTIME_SEED_MANIFEST_PATH:-}" ]]; then
  [[ "$seed_mode_active" == true ]] \
    || blockers+=("runtime seed evidence is present for pass type $AI_PASS_TYPE; seed mode is authorized only for bootstrap and adoption")
  [[ "$AI_RUNTIME_SEED_MANIFEST_PATH" == "$AI_REPORT_ROOT/tmp/$AI_ARTIFACT_STEM/runtime/runtime-seed-manifest.json" ]] \
    || blockers+=("runtime seed manifest path is not canonical: $AI_RUNTIME_SEED_MANIFEST_PATH")
  [[ -f "$AI_RUNTIME_SEED_MANIFEST_PATH" ]] \
    || blockers+=("runtime seed manifest is absent: ${AI_RUNTIME_SEED_MANIFEST_PATH#$AI_PROJECT_ROOT/}")
fi

if [[ -n "${AI_CAPTURE_STATUS_CONTRACT_ID:-}" ]]; then
  [[ "$AI_CAPTURE_STATUS_CONTRACT_ID" == darwin-script-child-status-propagation-v1 ]] \
    || blockers+=("unsupported capture status contract: $AI_CAPTURE_STATUS_CONTRACT_ID")
fi

if [[ -n "${AI_REQUIRED_TOOLS:-}" ]]; then
  tools=("${(@s: :)${AI_REQUIRED_TOOLS:-}}")
  tools=("${(@)tools:#}")
  local t
  for t in $tools; do [[ -z "$t" ]] || command -v -- "$t" >/dev/null 2>&1 || blockers+=("required tool is unavailable: $t"); done
fi

python3 -c 'import jsonschema' >/dev/null 2>&1 \
  || blockers+=("required Python package is unavailable: jsonschema (cli-post-pass.zsh finalization cannot validate metadata or continuation state without it)")

local reports_path="$AI_REPORT_ROOT/reports"
local metadata_reports_path="$AI_REPORT_ROOT/metadata-reports"
local expected_reports="$AI_PROJECT_ROOT/.dwbskim-private/build-report-logs/reports"
local expected_metadata_reports="$AI_PROJECT_ROOT/.dwbskim-private/build-report-logs/metadata-reports"
local allow_missing_private_artifact_links=false

[[ "$AI_PASS_TYPE" == bootstrap || "$AI_PASS_TYPE" == adoption ]] \
  && allow_missing_private_artifact_links=true

validate_private_artifact_link() {
  local logical_path="$1"
  local expected_target="$2"
  local label="$3"

  if [[ ! -e "$logical_path" && ! -L "$logical_path" ]]; then
    [[ "$allow_missing_private_artifact_links" == true ]] \
      || blockers+=("$label symlink is missing: $logical_path")
    return
  fi

  if [[ ! -L "$logical_path" ]]; then
    blockers+=("$label must be a symlink to ${expected_target#$AI_PROJECT_ROOT/}: $logical_path")
    return
  fi

  local resolved_target
  resolved_target="$(resolve_dir "$logical_path" 2>/dev/null)" || resolved_target=""

  [[ "$resolved_target" == "$expected_target" ]] \
    || blockers+=("$label symlink resolves to unexpected target: ${resolved_target:-unresolved}")
}

validate_private_artifact_link \
  "$reports_path" \
  "$expected_reports" \
  "reports"

validate_private_artifact_link \
  "$metadata_reports_path" \
  "$expected_metadata_reports" \
  "metadata-reports"

check_ds_store_repo() {
  local repo="$1"
  local label="$2"

  [[ -d "$repo/.git" ]] || return 0

  local exclude_file="$repo/.git/info/exclude"
  local ignore_ok=false

  if [[ -f "$repo/.gitignore" ]] \
    && grep -Eq '(^|/)\*\*/?\.DS_Store$|^\*\*/\.DS_Store$|^\.DS_Store$' "$repo/.gitignore"; then
    ignore_ok=true
  fi

  if [[ -f "$exclude_file" ]] \
    && grep -Eq '(^|/)\*\*/?\.DS_Store$|^\*\*/\.DS_Store$|^\.DS_Store$' "$exclude_file"; then
    ignore_ok=true
  fi

  [[ "$ignore_ok" == true ]] \
    || blockers+=("$label repository lacks recursive .DS_Store ignore coverage")

  local -a tracked_ds_store
  tracked_ds_store=(
    "${(@f)$(git -C "$repo" ls-files -- '*[/.]DS_Store' '.DS_Store' 2>/dev/null)}"
  )
  tracked_ds_store=("${(@)tracked_ds_store:#}")

  if (( ${#tracked_ds_store} )); then
    blockers+=(
      "$label repository has tracked .DS_Store entries; an authorized bootstrap, adoption, or maintenance pass must remove them from the Git index without deleting local Finder files"
    )
  fi
}

check_ds_store_repo "$AI_PROJECT_ROOT" project
check_ds_store_repo "$AI_PROJECT_ROOT/.dwbskim-private" private

check_skill_catalog_shape() {
  local store="${AI_SKILL_STORE_PATH:-$AI_PROJECT_ROOT/.dwbskim-private/.agents/skills-store}"
  local catalog="${AI_SKILL_CATALOG_PATH:-$AI_PROJECT_ROOT/.dwbskim-private/.agents/skills}"
  local lock="${AI_SKILLS_LOCK_PATH:-$AI_PROJECT_ROOT/.dwbskim-private/skills-lock.json}"

  [[ -d "$catalog" ]] || return 0

  local entry name resolved
  for entry in "$catalog"/*(N); do
    name="${entry:t}"
    if [[ ! -L "$entry" ]]; then
      blockers+=("discoverable skill catalog entry is not an activation symlink and therefore bypasses the authorization gate: $name")
      continue
    fi
    resolved="$(resolve_dir "$entry" 2>/dev/null)" || resolved=""
    [[ "$resolved" == "$store/$name" ]] \
      || blockers+=("discoverable skill $name resolves outside the authorized skill store: ${resolved:-unresolved}")
  done

  [[ -e "$lock" || ! -n "$(print -l -- "$catalog"/*(N))" ]] \
    || blockers+=("discoverable skills are present with no skills-lock.json; no skill may be discoverable without a current lock record")
}

check_skill_catalog_shape

local ready=true
(( ${#blockers} )) && ready=false
local patch diagnostics="${AI_RUNTIME_STATE_PATH:h}/cli-initialize-python-errors.log"
patch="$(python3 -c 'import json,sys,datetime
print(json.dumps({"workflow_version":"v2.4.1","initialization_finished_at":datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),"initialization_ready":sys.argv[1]=="true","initialization_blockers":[x for x in sys.argv[2].split("\n") if x]}))' "$ready" "${(j:\n:)blockers}" 2>>"$diagnostics")" || die 90 state "cannot encode initialization evidence; diagnostics retained at $diagnostics"
json_merge "$AI_RUNTIME_STATE_PATH" "$patch"
if [[ "$ready" != true ]]; then
  local b; for b in $blockers; do err readiness "$b"; done
  exit 10
fi
print -- "Initialization ready: $AI_ARTIFACT_STEM"