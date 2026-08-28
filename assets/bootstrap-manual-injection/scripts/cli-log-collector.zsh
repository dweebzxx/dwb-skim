#!/bin/zsh
# CLI Host Workflow Suite v2.4.1
# Automatic collector; never invokes or proxies a Code Agent.

set -u
setopt pipefail
zmodload zsh/datetime

readonly CLI_WORKFLOW_VERSION="v2.4.1"
readonly CLI_SCRIPT_NAME="${0:t}"
readonly CLI_STEM_RE='^[0-9]{2}-[0-9]{2}-[0-9]{2}_P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?_[a-z0-9]+(-[a-z0-9]+)*$'
readonly CLI_PASS_ID_RE='^P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?$'
err() { print -u2 -- "ERROR[$CLI_SCRIPT_NAME][$1]: $2"; }
need() { local n="$1"; [[ -n "${(P)n:-}" ]] || { err input "missing environment variable: $n"; exit 2; }; }
inside() { [[ "$1" == "$2" || "$1" == "$2"/* ]] || { err path "path escapes permitted root: $1"; exit 20; }; }
now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

write_state() {
  local state_status="$1" ready="$2" exit_status="$3" method="$4" failure="$5"
  local tmp="$AI_COLLECTOR_CONTROL_PATH/.collector-state.tmp.$$"
  python3 -c 'import json,os,sys
obj={"workflow_version":"v2.4.1","artifact_stem":sys.argv[2],"status":sys.argv[3],"clean_log_ready":sys.argv[4]=="true","raw_log_path":sys.argv[5],"clean_log_path":sys.argv[6],"collector_exit_status":int(sys.argv[7]),"completed_at":sys.argv[8],"normalization_method":sys.argv[9] or None,"failure":sys.argv[10] or None}
with open(sys.argv[1],"w",encoding="utf-8") as f:
 json.dump(obj,f,indent=2,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno())' "$tmp" "$AI_ARTIFACT_STEM" "$state_status" "$ready" "$AI_RAW_LOG_PATH" "$AI_CLEAN_LOG_PATH" "$exit_status" "$(now)" "$method" "$failure" || return 1
  mv -f -- "$tmp" "$AI_COLLECTOR_STATE_PATH" || return 1
}

fail_collect() {
  local code="$1" rule="$2" message="$3"
  write_state failed false "$code" "" "$rule: $message" 2>/dev/null || true
  [[ -n "${AI_COLLECTOR_PID_PATH:-}" ]] && rm -f -- "$AI_COLLECTOR_PID_PATH" 2>/dev/null || true
  print -- "[$(now)] collector failed; rule=$rule summary=$message raw_log_preserved=${AI_RAW_LOG_PATH#$AI_PROJECT_ROOT/}" >> "$AI_META_LOG_PATH" 2>/dev/null || true
  err "$rule" "$message"
  exit "$code"
}

check_common() {
  local n
  for n in AI_WORKFLOW_VERSION AI_PROJECT_ROOT AI_REPORT_ROOT AI_ARTIFACT_STEM AI_RAW_LOG_PATH AI_CLEAN_LOG_PATH AI_META_LOG_PATH AI_COLLECTOR_CONTROL_PATH AI_COLLECTOR_PID_PATH AI_COLLECTOR_STATE_PATH AI_RUNNER_CONTROL_PATH AI_POST_PASS_DONE_PATH; do need "$n"; done
  [[ "$AI_WORKFLOW_VERSION" == "$CLI_WORKFLOW_VERSION" ]] || fail_collect 2 version "expected $CLI_WORKFLOW_VERSION; received $AI_WORKFLOW_VERSION"
  [[ "$AI_REPORT_ROOT" == "$AI_PROJECT_ROOT/build-report-logs" ]] || fail_collect 20 path "invalid report root"
  [[ "$AI_ARTIFACT_STEM" =~ $CLI_STEM_RE ]] || fail_collect 20 identity "invalid artifact stem: $AI_ARTIFACT_STEM"
  [[ "$AI_RAW_LOG_PATH" == "$AI_REPORT_ROOT/logs/raw-logs/${AI_ARTIFACT_STEM}-raw.log" ]] || fail_collect 20 path "invalid raw-log path"
  [[ "$AI_CLEAN_LOG_PATH" == "$AI_REPORT_ROOT/logs/clean-logs/${AI_ARTIFACT_STEM}-clean.log" ]] || fail_collect 20 path "invalid clean-log path"
  for n in AI_RAW_LOG_PATH AI_CLEAN_LOG_PATH AI_META_LOG_PATH AI_COLLECTOR_CONTROL_PATH AI_COLLECTOR_PID_PATH AI_COLLECTOR_STATE_PATH AI_RUNNER_CONTROL_PATH AI_POST_PASS_DONE_PATH; do inside "${(P)n}" "$AI_REPORT_ROOT"; done
}

collect_phase() {
  mkdir -p -- "${AI_RAW_LOG_PATH:h}" "${AI_CLEAN_LOG_PATH:h}" "$AI_COLLECTOR_CONTROL_PATH" "$AI_RUNNER_CONTROL_PATH" "${AI_COLLECTOR_PID_PATH:h}" || fail_collect 40 collector "cannot create collector paths"
  print -r -- "$$" >| "$AI_COLLECTOR_PID_PATH" || fail_collect 40 collector "cannot record collector PID"
  print -r -- "{\"ready_at\":\"$(now)\",\"collector_pid\":$$}" >| "$AI_COLLECTOR_CONTROL_PATH/ready.json" || fail_collect 40 collector "cannot record readiness"
  print -- "[$(now)] collector ready; raw capture owner=/usr/bin/script" >> "$AI_META_LOG_PATH" || fail_collect 90 meta "cannot append collector readiness"

  local timeout="${AI_COLLECTOR_SESSION_TIMEOUT_SECONDS:-172800}"
  [[ "$timeout" == <-> && "$timeout" -ge 60 && "$timeout" -le 172800 ]] || fail_collect 2 input "collector session timeout must be 60-172800 seconds"
  local start=$EPOCHSECONDS
  until [[ -s "$AI_RUNNER_CONTROL_PATH/process-exit-recorded.json" ]]; do
    [[ -s "$AI_RUNNER_CONTROL_PATH/aborted.json" ]] \
      && fail_collect 40 aborted "session aborted by the Human Operator before process-exit evidence was recorded; raw log preserved"
    (( EPOCHSECONDS - start >= timeout )) && fail_collect 40 timeout "timed out waiting for process-exit evidence"
    sleep 1
  done
  [[ -f "$AI_RAW_LOG_PATH" ]] || fail_collect 40 capture "/usr/bin/script did not create the raw log"

  local tmp="$AI_CLEAN_LOG_PATH.tmp.$$" method="perl-ansi-and-cr-normalization"
  : >| "$tmp" || fail_collect 40 collector "cannot create temporary clean log"
  perl -pe 's/\e\[[0-?]*[ -\/]*[@-~]//g; s/\r(?!\n)/\n/g' "$AI_RAW_LOG_PATH" > "$tmp" \
    || { rm -f -- "$tmp" 2>/dev/null || true; fail_collect 40 normalization "clean-log normalization failed"; }
  mv -f -- "$tmp" "$AI_CLEAN_LOG_PATH" || { rm -f -- "$tmp" 2>/dev/null || true; fail_collect 40 normalization "cannot atomically install clean log"; }
  write_state succeeded true 0 "$method" "" || fail_collect 90 evidence "cannot atomically record collector state"
  print -- "[$(now)] collector clean-log ready; method=$method raw_bytes=$(wc -c < "$AI_RAW_LOG_PATH" | tr -d ' ') clean_bytes=$(wc -c < "$AI_CLEAN_LOG_PATH" | tr -d ' ')" >> "$AI_META_LOG_PATH" || fail_collect 90 meta "cannot append clean-log readiness"
  rm -f -- "$AI_COLLECTOR_PID_PATH" 2>/dev/null || true
}

close_phase() {
  [[ -s "$AI_COLLECTOR_STATE_PATH" ]] || { err collector "collector state is missing"; exit 40; }
  [[ -s "$AI_POST_PASS_DONE_PATH" ]] || { err collector "post-pass completion evidence is missing"; exit 40; }
  python3 -c 'import json,sys
s=json.load(open(sys.argv[1],encoding="utf-8"))
if s.get("status")!="succeeded" or s.get("clean_log_ready") is not True or s.get("collector_exit_status")!=0: raise SystemExit(1)' "$AI_COLLECTOR_STATE_PATH" || { err collector "collector state is not successful"; exit 40; }
  print -r -- "{\"closed_at\":\"$(now)\"}" >| "$AI_COLLECTOR_CONTROL_PATH/closed.json" || { err collector "cannot record collector closure"; exit 40; }
  print -- "[$(now)] collector closure recorded after post-pass evidence" >> "$AI_META_LOG_PATH" || { err meta "cannot append collector closure"; exit 90; }
}

check_common
case "${1:-collect}" in
  collect) collect_phase ;;
  close) close_phase ;;
  *) err input "usage: $CLI_SCRIPT_NAME {collect|close}"; exit 2 ;;
esac
