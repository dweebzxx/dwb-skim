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

local state="${AI_RUNTIME_STATE_PATH:-}"
local stem=""
local supplied_lifecycle_session_id=""
local grace=10
while (( $# )); do
  case "$1" in
    --runtime-state) (( $# >= 2 )) || die 2 input "missing value for --runtime-state"; state="$2"; shift 2 ;;
    --artifact-stem) (( $# >= 2 )) || die 2 input "missing value for --artifact-stem"; stem="$2"; shift 2 ;;
    --lifecycle-session-id) (( $# >= 2 )) || die 2 input "missing value for --lifecycle-session-id"; supplied_lifecycle_session_id="$2"; shift 2 ;;
    --grace-seconds) (( $# >= 2 )) || die 2 input "missing value for --grace-seconds"; grace="$2"; shift 2 ;;
    *) die 2 input "unknown option: $1" ;;
  esac
done
[[ -n "$state" && -n "$stem" && -n "$supplied_lifecycle_session_id" ]] || die 70 authorization "required: --runtime-state --artifact-stem --lifecycle-session-id"
[[ "$stem" =~ $CLI_STEM_RE ]] || die 20 identity "invalid artifact stem: $stem"
[[ "$grace" == <-> && "$grace" -ge 1 && "$grace" -le 60 ]] || die 2 input "grace period must be 1-60 seconds"
local record="${state:h}/abort-records.jsonl"
mkdir -p -- "${record:h}" || die 90 record "cannot create abort-record parent"

append_record() {
  local outcome="$1" pid="${2:-}" binary="${3:-}" recorded_marker="${4:-}" observed_marker="${5:-}" observed_command="${6:-}" pgid="${7:-}" detail="${8:-}"
  python3 -c 'import datetime,json,os,sys

def positive_int_or_none(value):
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None

obj={
 "timestamp":datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
 "artifact_stem":sys.argv[2] or None,
 "lifecycle_session_id":sys.argv[3] or None,
 "target_pid":positive_int_or_none(sys.argv[4]),
 "target_pid_text":sys.argv[4] or None,
 "code_agent_binary":sys.argv[5] or None,
 "recorded_process_start_marker":sys.argv[6] or None,
 "observed_process_start_marker":sys.argv[7] or None,
 "observed_command":sys.argv[8] or None,
 "process_group_id":positive_int_or_none(sys.argv[9]),
 "process_group_id_text":sys.argv[9] or None,
 "outcome":sys.argv[10],
 "detail":sys.argv[11] or None
}
with open(sys.argv[1],"a",encoding="utf-8") as f:
 f.write(json.dumps(obj,sort_keys=True)+"\n"); f.flush(); os.fsync(f.fileno())' "$record" "$stem" "$supplied_lifecycle_session_id" "$pid" "$binary" "$recorded_marker" "$observed_marker" "$observed_command" "$pgid" "$outcome" "$detail" 2>/dev/null || die 90 record "cannot append abort record"
}

local parsed
parsed="$(python3 - "$state" "$stem" "$supplied_lifecycle_session_id" <<'PY'
import json,sys
path,stem,session=sys.argv[1:]
data=json.load(open(path,encoding="utf-8"))
if data.get("artifact_stem")!=stem: raise SystemExit("artifact-stem-mismatch")
identity=data.get("runtime_identity")
if not isinstance(identity,dict): raise SystemExit("runtime-identity-missing")
required={"pass_id","artifact_stem","lifecycle_session_id","launcher_pid","launcher_process_start_marker","capture_pid","capture_process_start_marker","code_agent_pid","code_agent_binary","code_agent_process_start_marker","process_group_id","raw_log_path","registered_at","active"}
missing=sorted(required-set(identity))
if missing: raise SystemExit("runtime-identity-fields-missing:"+",".join(missing))
if identity.get("pass_id")!=data.get("pass_id") or identity.get("artifact_stem")!=stem: raise SystemExit("runtime-identity-pass-mismatch")
if identity.get("lifecycle_session_id")!=session: raise SystemExit("lifecycle-session-mismatch")
if identity.get("active") is not True: raise SystemExit("no-active-code-agent")
values=[identity.get("code_agent_pid"),identity.get("code_agent_binary"),identity.get("code_agent_process_start_marker"),identity.get("process_group_id"),data.get("runner_control_path")]
print("\t".join("" if v is None else str(v) for v in values))
PY
)" || {
  append_record "identity-parse-or-contract-failed" "" "" "" "" "" "" "runtime state missing, stale, malformed, or mismatched"
  die 30 identity "runtime identity could not be verified; diagnostic appended to $record"
}

local pid binary recorded_marker pgid runner_control
IFS=$'\t' read -r pid binary recorded_marker pgid runner_control <<< "$parsed"
[[ "$pid" == <-> && -n "$binary" && "$binary" == /* && -n "$recorded_marker" ]] || {
  append_record "identity-malformed" "$pid" "$binary" "$recorded_marker" "" "" "$pgid" "required Code Agent identity is incomplete"
  die 30 identity "Code Agent identity is incomplete"
}
kill -0 "$pid" 2>/dev/null || {
  append_record "stale-process-identity" "$pid" "$binary" "$recorded_marker" "" "" "$pgid" "recorded PID is no longer active"
  die 30 identity "recorded Code Agent PID is no longer active: $pid"
}
local observed_marker command observed_pgid
observed_marker="$(LC_ALL=C ps -p "$pid" -o lstart= 2>/dev/null | awk '{$1=$1; print}')"
command="$(ps -p "$pid" -o command= 2>/dev/null)"
observed_pgid="$(ps -p "$pid" -o pgid= 2>/dev/null | awk '{$1=$1; print}')"
[[ -n "$observed_marker" && "$observed_marker" == "$recorded_marker" ]] || {
  append_record "process-start-identity-mismatch" "$pid" "$binary" "$recorded_marker" "$observed_marker" "$command" "$pgid" "PID reuse or process replacement detected"
  die 30 identity "recorded PID start marker does not match"
}
[[ -n "$command" && ( "$command" == "$binary" || "$command" == "${binary} "* ) ]] || {
  append_record "process-executable-identity-mismatch" "$pid" "$binary" "$recorded_marker" "$observed_marker" "$command" "$pgid" "executable identity mismatch"
  die 30 identity "recorded PID does not match the Code Agent executable"
}
if [[ -n "$pgid" ]]; then
  [[ "$pgid" == <-> && "$observed_pgid" == "$pgid" ]] || {
    append_record "process-group-identity-mismatch" "$pid" "$binary" "$recorded_marker" "$observed_marker" "$command" "$pgid" "process-group identity mismatch"
    die 30 identity "recorded process group does not match"
  }
fi

local target="$pid" target_label="pid"
if [[ "${AI_ABORT_INCLUDE_PROCESS_GROUP:-0}" == 1 && -n "$pgid" ]]; then
  target="-$pgid"
  target_label="process-group"
fi
kill -TERM "$target" 2>/dev/null || {
  append_record "term-failed" "$pid" "$binary" "$recorded_marker" "$observed_marker" "$command" "$pgid" "failed to signal $target_label"
  die 80 abort "failed to send TERM to workflow-owned $target_label"
}
local elapsed=0
while kill -0 "$pid" 2>/dev/null && (( elapsed < grace )); do sleep 1; (( elapsed++ )); done
local outcome=terminated-term
if kill -0 "$pid" 2>/dev/null; then
  kill -KILL "$target" 2>/dev/null || {
    append_record "kill-failed" "$pid" "$binary" "$recorded_marker" "$observed_marker" "$command" "$pgid" "failed to signal $target_label"
    die 80 abort "failed to send KILL to workflow-owned $target_label"
  }
  outcome=terminated-kill
fi
append_record "$outcome" "$pid" "$binary" "$recorded_marker" "$observed_marker" "$command" "$pgid" "append-only abort evidence; automatic lifecycle state not rewritten"

# Release the collector, which would otherwise wait for process-exit evidence the
# terminated launcher can no longer write. Confined to this pass's runtime tree.
if [[ -n "$runner_control" && "$runner_control" == "${state:h:h}"/* ]]; then
  mkdir -p -- "$runner_control" 2>/dev/null \
    && print -r -- "{\"aborted_at\":\"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\",\"target_label\":\"$target_label\"}" \
       >| "$runner_control/aborted.json" 2>/dev/null \
    || err abort "could not record the collector abort release; the collector may wait for its configured timeout"
fi
print -- "Workflow-owned Code Agent session terminated; append-only abort evidence recorded"
exit 80
