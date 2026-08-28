#!/bin/zsh
# CLI Host Workflow Suite v2.4.1
# Lifecycle-control and evidence component. Never invokes a Code Agent binary.

set -u
setopt pipefail

readonly CLI_WORKFLOW_VERSION="v2.4.1"
readonly CLI_SCRIPT_NAME="${0:t}"
readonly CLI_STEM_RE='^[0-9]{2}-[0-9]{2}-[0-9]{2}_P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?_[a-z0-9]+(-[a-z0-9]+)*$'
readonly CLI_PASS_ID_RE='^P[0-9]*[1-9][0-9]*(\.[0-9]*[1-9][0-9]*)?$'
# The only accepted platform status contract (Host Guide 0.4, 11.5). The
# capture return value is adopted as the Code Agent status under this contract
# alone, and only after live direct-child registration succeeded.
readonly CLI_CAPTURE_STATUS_CONTRACT_ID='darwin-script-child-status-propagation-v1'
readonly CLI_TIMESTAMP_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

err() { print -u2 -- "ERROR[$CLI_SCRIPT_NAME][$1]: $2"; }
die() { local c="$1" s="$2" m="$3"; err "$s" "$m"; exit "$c"; }
need() { local n="$1"; [[ -n "${(P)n:-}" ]] || die 2 input "missing environment variable: $n"; }
resolve_dir() { (cd -P -- "$1" 2>/dev/null && pwd -P) || return 1; }
inside() { [[ "$1" == "$2" || "$1" == "$2"/* ]] || die 20 path "path escapes permitted root: $1"; }
now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

atomic_merge() {
  local patch="$1" diagnostics="$AI_RUNNER_CONTROL_PATH/python-errors.log"
  python3 -c 'import json,os,sys,tempfile
p,patch=sys.argv[1:3]
data={}
if os.path.exists(p) and os.path.getsize(p):
 data=json.load(open(p,encoding="utf-8"))
data.update(json.loads(patch))
os.makedirs(os.path.dirname(p),exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix=".runner-state.",dir=os.path.dirname(p))
try:
 with os.fdopen(fd,"w",encoding="utf-8") as f:
  json.dump(data,f,indent=2,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno())
 os.replace(tmp,p)
except Exception:
 try: os.unlink(tmp)
 except OSError: pass
 raise' "$AI_RUNTIME_STATE_PATH" "$patch" 2>>"$diagnostics" \
    || die 90 state "cannot update runtime state; diagnostics: ${diagnostics#$AI_PROJECT_ROOT/}"
}

check_common() {
  local n root
  for n in AI_WORKFLOW_VERSION AI_PROJECT_ROOT AI_REPORT_ROOT AI_PASS_ID AI_ARTIFACT_STEM AI_CODE_AGENT AI_MODEL AI_PROMPT_PATH AI_LAUNCHER_PATH AI_RAW_LOG_PATH AI_CLEAN_LOG_PATH AI_META_LOG_PATH AI_RUNTIME_STATE_PATH AI_INVOCATION_MANIFEST_PATH AI_INVOCATION_ARGUMENTS_PATH AI_INVOCATION_AUTHORIZATION_PATH AI_SELECTION_EVIDENCE_PATH AI_INVOCATION_CONTRACT_PATH AI_RUNNER_CONTROL_PATH AI_COLLECTOR_CONTROL_PATH AI_COLLECTOR_STATE_PATH; do need "$n"; done
  [[ "$AI_WORKFLOW_VERSION" == "$CLI_WORKFLOW_VERSION" ]] || die 2 version "expected $CLI_WORKFLOW_VERSION; received $AI_WORKFLOW_VERSION"
  root="$(resolve_dir "$AI_PROJECT_ROOT")" || die 20 project-root "cannot resolve project root: $AI_PROJECT_ROOT"
  [[ "$root" == "$AI_PROJECT_ROOT" ]] || die 20 project-root "AI_PROJECT_ROOT must be resolved: $root"
  [[ "$AI_REPORT_ROOT" == "$AI_PROJECT_ROOT/build-report-logs" ]] || die 20 path "invalid report root"
  [[ "$AI_PASS_ID" =~ $CLI_PASS_ID_RE ]] || die 20 identity "invalid pass ID: $AI_PASS_ID"
  [[ "$AI_ARTIFACT_STEM" =~ $CLI_STEM_RE ]] || die 20 identity "invalid artifact stem: $AI_ARTIFACT_STEM"
  [[ "$AI_PROMPT_PATH" == "$AI_REPORT_ROOT/prompts/${AI_ARTIFACT_STEM}-prompt.txt" ]] || die 20 identity "invalid prompt path"
  [[ "$AI_LAUNCHER_PATH" == "$AI_REPORT_ROOT/launchers/${AI_ARTIFACT_STEM}-launcher.zsh" ]] || die 20 identity "invalid launcher path"
  [[ "$AI_RAW_LOG_PATH" == "$AI_REPORT_ROOT/logs/raw-logs/${AI_ARTIFACT_STEM}-raw.log" ]] || die 20 identity "invalid raw-log path"
  [[ "$AI_CLEAN_LOG_PATH" == "$AI_REPORT_ROOT/logs/clean-logs/${AI_ARTIFACT_STEM}-clean.log" ]] || die 20 identity "invalid clean-log path"
  [[ "$AI_META_LOG_PATH" == "$AI_REPORT_ROOT/logs/meta-logs/${AI_ARTIFACT_STEM}-meta.log" ]] || die 20 identity "invalid meta-log path"
  for n in AI_RUNTIME_STATE_PATH AI_INVOCATION_MANIFEST_PATH AI_INVOCATION_ARGUMENTS_PATH AI_INVOCATION_AUTHORIZATION_PATH AI_SELECTION_EVIDENCE_PATH AI_INVOCATION_CONTRACT_PATH AI_RUNNER_CONTROL_PATH AI_COLLECTOR_CONTROL_PATH AI_COLLECTOR_STATE_PATH; do inside "${(P)n}" "$AI_REPORT_ROOT"; done
  mkdir -p -- "$AI_RUNNER_CONTROL_PATH" || die 90 runtime "cannot create runner control path"
}

validate_contract() {
  [[ -s "$AI_PROMPT_PATH" ]] || die 20 prompt "saved prompt missing or empty: $AI_PROMPT_PATH"
  [[ -s "$AI_LAUNCHER_PATH" && -x "$AI_LAUNCHER_PATH" ]] || die 20 launcher "saved launcher missing, empty, or non-executable"
  [[ -s "$AI_INVOCATION_MANIFEST_PATH" ]] || die 20 invocation "invocation manifest missing or empty"
  [[ -s "$AI_INVOCATION_ARGUMENTS_PATH" ]] || die 20 invocation "structured argv record missing or empty"
  [[ -s "$AI_INVOCATION_AUTHORIZATION_PATH" ]] || die 20 invocation "invocation authorization record missing or empty"
  [[ -s "$AI_SELECTION_EVIDENCE_PATH" ]] || die 20 invocation "selection-data evidence record missing or empty"
  [[ -s "$AI_INVOCATION_CONTRACT_PATH" ]] || die 20 invocation "invocation contract snapshot missing or empty"
  [[ -x /usr/bin/script ]] || die 10 prerequisite "/usr/bin/script is unavailable"

  local diagnostics="$AI_RUNNER_CONTROL_PATH/invocation-validation-errors.log"
  python3 - "$AI_INVOCATION_MANIFEST_PATH" "$AI_INVOCATION_ARGUMENTS_PATH" "$AI_INVOCATION_AUTHORIZATION_PATH" "$AI_SELECTION_EVIDENCE_PATH" "$AI_INVOCATION_CONTRACT_PATH" "$AI_WORKFLOW_VERSION" "$AI_PROJECT_ROOT" "$AI_REPORT_ROOT" "$AI_PASS_ID" "$AI_ARTIFACT_STEM" "$AI_CODE_AGENT" "$AI_MODEL" "${AI_EFFORT:-}" "$AI_PROMPT_PATH" "$AI_LAUNCHER_PATH" "$AI_RAW_LOG_PATH" "$AI_CLEAN_LOG_PATH" "$AI_META_LOG_PATH" <<'PY' 2>>"$diagnostics" \
    || die 40 invocation "invocation contract validation failed; diagnostics: ${diagnostics#$AI_PROJECT_ROOT/}"
import json, os, re, sys
(
 manifest_path, argv_path, authorization_path, selection_path, contract_path,
 version, project_root, report_root, pass_id, stem, family, model, effort,
 prompt_path, launcher_path, raw_path, clean_path, meta_path
)=sys.argv[1:]

class DuplicateKey(ValueError): pass
def no_dupes(pairs):
 out={}
 for k,v in pairs:
  if k in out: raise DuplicateKey(f"duplicate JSON key: {k}")
  out[k]=v
 return out
def load(path):
 with open(path,encoding="utf-8") as f:
  obj=json.load(f,object_pairs_hook=no_dupes)
 if not isinstance(obj,dict): raise SystemExit(f"record root must be an object: {path}")
 return obj

m=load(manifest_path); a=load(authorization_path); s=load(selection_path); c=load(contract_path); ar=load(argv_path)
required={
 "workflow_version","artifact_stem","pass_id","code_agent","model","effort","project_root",
 "prompt_path","launcher_path","raw_log_path","clean_log_path","meta_log_path","invocation_mode",
 "direct_invocation","interactive_capture","executable_path","arguments_path",
 "argv_count",
 "model_confirmation_reference","authorization_reference","authorization_record_path",
 "selection_data_reference","selection_data_path","invocation_contract_reference",
 "invocation_contract_path"
}
missing=sorted(required-set(m))
if missing: raise SystemExit("missing manifest fields: "+", ".join(missing))
prohibited={"command","command_string","shell_command","command_text","script_text"}
if prohibited.intersection(m): raise SystemExit("shell-command strings are prohibited")
expected={
 "workflow_version":version,"artifact_stem":stem,"pass_id":pass_id,"code_agent":family,
 "model":model,"effort":effort or None,"project_root":project_root,"prompt_path":prompt_path,
 "launcher_path":launcher_path,"raw_log_path":raw_path,"clean_log_path":clean_path,
 "meta_log_path":meta_path,"invocation_mode":"direct-interactive-launcher","direct_invocation":True,
 "interactive_capture":"/usr/bin/script","arguments_path":argv_path,
 "authorization_record_path":authorization_path,"selection_data_path":selection_path,
 "invocation_contract_path":contract_path
}
for k,v in expected.items():
 if m.get(k)!=v: raise SystemExit(f"manifest mismatch for {k}")

if set(ar)!={"schema_version","executable","argv","bindings"}: raise SystemExit("structured argv record has unexpected or missing keys")
if ar.get("schema_version")!="v2.4.1": raise SystemExit("structured argv schema_version mismatch")
argv=ar.get("argv")
if not isinstance(argv,list) or not argv or not all(isinstance(x,str) and x and "\x00" not in x and "\r" not in x and "\n" not in x for x in argv):
 raise SystemExit("argv must be a nonempty array of nonempty single-line strings")
executable=ar.get("executable")
if not isinstance(executable,str) or not os.path.isabs(executable): raise SystemExit("agent executable must be absolute")
if argv[0]!=executable or m["executable_path"]!=executable: raise SystemExit("executable/argv mismatch")
if m["argv_count"]!=len(argv): raise SystemExit("argv_count mismatch")
resolved=os.path.realpath(executable); base=os.path.basename(resolved)
if base in {"sh","zsh","bash","dash","ksh","fish","env","node","nodejs","npx","bun","deno","python","python3","ruby","perl"} or resolved=="/usr/bin/env":
 raise SystemExit(f"shell, interpreter, or environment proxy executable is prohibited: {base}")
if os.path.splitext(base)[1].lower() in {".js",".mjs",".cjs",".py",".rb",".pl",".sh",".zsh",".bash"}:
 raise SystemExit(f"interpreted wrapper script is prohibited as the Code Agent executable: {base}; resolve the family's native binary per Host Guide 9.6")
try:
 with open(resolved,"rb") as _f: _head=_f.read(2)
except OSError as _e: raise SystemExit(f"cannot read Code Agent executable: {_e}")
if _head==b"#!":
 raise SystemExit(f"Code Agent executable is an interpreted script, not a native binary: {resolved}; resolve the family's native binary per Host Guide 9.6")
if any(x in {"-c","-lc","--command"} for x in argv[1:]): raise SystemExit("command-mode shell reparsing argument is prohibited")
if any(re.search(r"(?:\$\(|`|<\(|>\()",x) for x in argv[1:]): raise SystemExit("command-substitution syntax is prohibited in argv")

bindings=ar.get("bindings")
if not isinstance(bindings,dict): raise SystemExit("bindings must be an object")
used=set()
for name,b in bindings.items():
 if not isinstance(b,dict) or set(b)-{"flag_index","value_index","flag","value"}: raise SystemExit(f"invalid binding: {name}")
 for field in ("flag_index","value_index"):
  idx=b.get(field)
  if idx is None: continue
  if not isinstance(idx,int) or idx<=0 or idx>=len(argv): raise SystemExit(f"invalid {name}.{field}")
  if idx in used: raise SystemExit("duplicate/conflicting argv binding index")
  used.add(idx)
 if b.get("flag_index") is not None and argv[b["flag_index"]]!=b.get("flag"): raise SystemExit(f"{name} flag binding mismatch")
 if b.get("value_index") is not None and argv[b["value_index"]]!=b.get("value"): raise SystemExit(f"{name} value binding mismatch")
if (bindings.get("model") or {}).get("value")!=model: raise SystemExit("model binding mismatch")
if effort and (bindings.get("effort") or {}).get("value")!=effort: raise SystemExit("effort binding mismatch")

if a.get("authorized") is not True or a.get("human_confirmed") is not True: raise SystemExit("invocation is not Human-authorized")
if s.get("approved") is not True or c.get("approved") is not True: raise SystemExit("selection or invocation contract is not approved")
PY

  print -r -- "{\"validated_at\":\"$(now)\"}" >| "$AI_RUNNER_CONTROL_PATH/validated.json" || die 90 evidence "cannot record invocation validation"
  print -- "[$(now)] invocation validated; direct launcher required; family=$AI_CODE_AGENT model=$AI_MODEL effort=${AI_EFFORT:-null}" >> "$AI_META_LOG_PATH" || die 90 meta "cannot append invocation validation"
}

begin_boundary() {
  [[ -s "$AI_RUNNER_CONTROL_PATH/validated.json" ]] || die 40 invocation "validate operation has not completed"
  [[ -s "$AI_COLLECTOR_CONTROL_PATH/ready.json" ]] || die 40 collector "collector is not ready"
  need AI_LIFECYCLE_SESSION_ID
  need AI_LAUNCHER_PID
  need AI_LAUNCHER_PROCESS_START_MARKER
  [[ "$AI_LAUNCHER_PID" == <-> ]] || die 20 process "invalid launcher PID"
  kill -0 "$AI_LAUNCHER_PID" 2>/dev/null || die 40 process "launcher PID is not active"
  local diagnostics="$AI_RUNNER_CONTROL_PATH/begin-errors.log" prior
  prior="$(python3 -c 'import json,sys
x=json.load(open(sys.argv[1],encoding="utf-8")); print(str(x.get("agent_started")).lower())' "$AI_RUNTIME_STATE_PATH" 2>>"$diagnostics")" || die 90 state "cannot read runtime state"
  [[ "$prior" == false ]] || die 30 lifecycle "durable start boundary requires agent_started=false"
  local patch
  patch="$(python3 -c 'import json,sys,datetime
now=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
print(json.dumps({"agent_started":True,"agent_started_at":now,"runtime_identity":{"pass_id":sys.argv[7],"artifact_stem":sys.argv[8],"lifecycle_session_id":sys.argv[1],"launcher_pid":int(sys.argv[2]),"launcher_process_start_marker":sys.argv[3],"capture_pid":None,"capture_process_start_marker":None,"code_agent_pid":None,"code_agent_binary":None,"code_agent_process_start_marker":None,"process_group_id":None,"raw_log_path":sys.argv[4],"registered_at":None,"active":True},"invocation_manifest_path":sys.argv[5],"invocation_arguments_path":sys.argv[6]}))' "$AI_LIFECYCLE_SESSION_ID" "$AI_LAUNCHER_PID" "$AI_LAUNCHER_PROCESS_START_MARKER" "$AI_RAW_LOG_PATH" "$AI_INVOCATION_MANIFEST_PATH" "$AI_INVOCATION_ARGUMENTS_PATH" "$AI_PASS_ID" "$AI_ARTIFACT_STEM" 2>>"$diagnostics")" || die 90 state "cannot encode start boundary"
  atomic_merge "$patch"
  print -r -- "{\"started_at\":\"$(now)\",\"lifecycle_session_id\":\"$AI_LIFECYCLE_SESSION_ID\"}" >| "$AI_RUNNER_CONTROL_PATH/start-boundary.json" || die 90 evidence "cannot record start boundary"
  print -- "[$(now)] durable agent-start boundary established; lifecycle_session_id=$AI_LIFECYCLE_SESSION_ID launcher_pid=$AI_LAUNCHER_PID" >> "$AI_META_LOG_PATH" || die 90 meta "cannot append start boundary"
}

register_process() {
  [[ -s "$AI_RUNNER_CONTROL_PATH/start-boundary.json" ]] || die 30 lifecycle "begin operation has not completed"
  need AI_CAPTURE_PID
  need AI_CAPTURE_PROCESS_START_MARKER
  need AI_CODE_AGENT_PID
  need AI_CODE_AGENT_BINARY
  need AI_CODE_AGENT_PROCESS_START_MARKER
  [[ "$AI_CAPTURE_PID" == <-> && "$AI_CODE_AGENT_PID" == <-> ]] || die 20 process "invalid capture or Code Agent PID"
  [[ "$AI_CAPTURE_PID" != "$AI_CODE_AGENT_PID" ]] || die 20 process "capture and Code Agent PIDs must be distinct"
  [[ "$AI_CODE_AGENT_BINARY" == /* ]] || die 20 process "Code Agent binary identity must be absolute"
  kill -0 "$AI_CAPTURE_PID" 2>/dev/null || die 40 process "registered /usr/bin/script process is not active"
  kill -0 "$AI_CODE_AGENT_PID" 2>/dev/null || die 40 process "registered Code Agent process is not active"
  # Live registration is issued by the detached watcher while both processes
  # are alive (Host Guide 9.6). The parent chain is verified here, not assumed:
  # the capture process must be a child of the recorded launcher, and the Code
  # Agent must be the direct child of the capture process.
  local launcher_pid capture_parent agent_parent
  launcher_pid="$(python3 -c 'import json,sys
identity=(json.load(open(sys.argv[1],encoding="utf-8")).get("runtime_identity") or {})
value=identity.get("launcher_pid")
print("" if value is None else int(value))' "$AI_RUNTIME_STATE_PATH")" \
    || die 90 state "cannot read recorded launcher identity"
  [[ -n "$launcher_pid" ]] || die 30 lifecycle "launcher identity is not recorded; begin has not completed"
  capture_parent="$(ps -p "$AI_CAPTURE_PID" -o ppid= 2>/dev/null | tr -d ' ')" \
    || die 40 process "cannot read capture-process parent"
  agent_parent="$(ps -p "$AI_CODE_AGENT_PID" -o ppid= 2>/dev/null | tr -d ' ')" \
    || die 40 process "cannot read Code Agent parent"
  [[ "$capture_parent" == "$launcher_pid" ]] \
    || die 40 process "capture process is not a child of the registered launcher: ppid=$capture_parent launcher=$launcher_pid"
  [[ "$agent_parent" == "$AI_CAPTURE_PID" ]] \
    || die 40 process "Code Agent is not the direct child of the capture process: ppid=$agent_parent capture=$AI_CAPTURE_PID"
  local manifest_binary
  manifest_binary="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["executable_path"])' "$AI_INVOCATION_MANIFEST_PATH")" || die 90 state "cannot read accepted executable identity"
  [[ "$AI_CODE_AGENT_BINARY" == "$manifest_binary" ]] || die 40 process "Code Agent binary does not match validated invocation contract"
  local process_group_json=null
  if [[ -n "${AI_PROCESS_GROUP_ID:-}" ]]; then
    [[ "$AI_PROCESS_GROUP_ID" == <-> ]] || die 20 process "invalid process group ID"
    process_group_json="$AI_PROCESS_GROUP_ID"
  fi
  local patch
  patch="$(python3 -c 'import json,sys,datetime
state=json.load(open(sys.argv[1],encoding="utf-8")); identity=state.get("runtime_identity") or {}
identity.update({"capture_pid":int(sys.argv[2]),"capture_process_start_marker":sys.argv[3],"code_agent_pid":int(sys.argv[4]),"code_agent_binary":sys.argv[5],"code_agent_process_start_marker":sys.argv[6],"process_group_id":None if sys.argv[7]=="null" else int(sys.argv[7]),"raw_log_path":sys.argv[8],"registered_at":datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),"active":True})
print(json.dumps({"runtime_identity":identity}))' "$AI_RUNTIME_STATE_PATH" "$AI_CAPTURE_PID" "$AI_CAPTURE_PROCESS_START_MARKER" "$AI_CODE_AGENT_PID" "$AI_CODE_AGENT_BINARY" "$AI_CODE_AGENT_PROCESS_START_MARKER" "$process_group_json" "$AI_RAW_LOG_PATH")" || die 90 state "cannot encode process registration"
  atomic_merge "$patch"
  print -r -- "{\"registered_at\":\"$(now)\",\"capture_pid\":$AI_CAPTURE_PID,\"code_agent_pid\":$AI_CODE_AGENT_PID,\"registered_live\":true}" >| "$AI_RUNNER_CONTROL_PATH/registered.json" || die 90 evidence "cannot record process registration"
  print -- "[$(now)] capture and Code Agent identities registered live; capture_pid=$AI_CAPTURE_PID code_agent_pid=$AI_CODE_AGENT_PID raw_log=${AI_RAW_LOG_PATH#$AI_PROJECT_ROOT/}" >> "$AI_META_LOG_PATH" || die 90 meta "cannot append process registration"
}

complete_process_phase() {
  [[ -s "$AI_RUNNER_CONTROL_PATH/registered.json" ]] || die 30 lifecycle "register operation has not completed"
  need AI_CAPTURE_EXIT_STATUS
  need AI_CODE_AGENT_EXIT_STATUS_AVAILABLE
  need AI_CAPTURE_STATUS_CONTRACT_ID
  need AI_AGENT_EXITED_AT
  [[ "$AI_CAPTURE_EXIT_STATUS" == <-> && "$AI_CAPTURE_EXIT_STATUS" -ge 0 && "$AI_CAPTURE_EXIT_STATUS" -le 255 ]] || die 20 exit "invalid capture-process exit status"
  [[ "$AI_CODE_AGENT_EXIT_STATUS_AVAILABLE" == true || "$AI_CODE_AGENT_EXIT_STATUS_AVAILABLE" == false ]] || die 20 exit "AI_CODE_AGENT_EXIT_STATUS_AVAILABLE must be true or false"
  [[ "$AI_AGENT_EXITED_AT" =~ $CLI_TIMESTAMP_RE ]] || die 20 exit "AI_AGENT_EXITED_AT must be a UTC timestamp of the form YYYY-MM-DDTHH:MM:SSZ"

  # Status-contract gates. All three must hold before the capture return value
  # may be adopted as the Code Agent status (Host Guide 0.4, 11.5, 15.3).
  local contract_ok=true contract_reason=""
  [[ "$AI_CAPTURE_STATUS_CONTRACT_ID" == "$CLI_CAPTURE_STATUS_CONTRACT_ID" ]] \
    || die 20 exit "unsupported capture status contract: $AI_CAPTURE_STATUS_CONTRACT_ID"
  if [[ "$(uname -s 2>/dev/null)" != Darwin ]]; then
    contract_ok=false
    contract_reason="platform is not Darwin; the named capture status contract does not hold"
  elif [[ ! -x /usr/bin/script ]]; then
    contract_ok=false
    contract_reason="the system /usr/bin/script is unavailable"
  else
    local registered_live
    registered_live="$(python3 -c 'import json,sys
print(str(json.load(open(sys.argv[1],encoding="utf-8")).get("registered_live") is True).lower())' "$AI_RUNNER_CONTROL_PATH/registered.json")" \
      || die 90 state "cannot inspect live registration evidence"
    if [[ "$registered_live" != true ]]; then
      contract_ok=false
      contract_reason="live direct-child registration did not succeed"
    fi
  fi

  # Under the contract the runner derives the status; it does not accept a
  # launcher-supplied value on trust. A supplied value that disagrees with the
  # derived one is contradictory lifecycle evidence and fails closed.
  local code_agent_status_json=null status_source_json=null
  if [[ "$contract_ok" == true ]]; then
    code_agent_status_json="$AI_CAPTURE_EXIT_STATUS"
    status_source_json="\"$CLI_CAPTURE_STATUS_CONTRACT_ID\""
    if [[ "$AI_CODE_AGENT_EXIT_STATUS_AVAILABLE" == true && -n "${AI_CODE_AGENT_EXIT_STATUS:-}" ]]; then
      [[ "$AI_CODE_AGENT_EXIT_STATUS" == "$AI_CAPTURE_EXIT_STATUS" ]] \
        || die 30 exit "supplied Code Agent status $AI_CODE_AGENT_EXIT_STATUS contradicts the propagated capture status $AI_CAPTURE_EXIT_STATUS"
    fi
  else
    [[ "$AI_CODE_AGENT_EXIT_STATUS_AVAILABLE" == false ]] \
      || die 30 exit "Code Agent status was declared available but the status contract did not hold: $contract_reason"
    [[ -z "${AI_CODE_AGENT_EXIT_STATUS:-}" ]] || die 20 exit "unavailable Code Agent exit status must be empty"
  fi

  local patch
  patch="$(python3 -c 'import json,sys
state=json.load(open(sys.argv[1],encoding="utf-8")); identity=state.get("runtime_identity") or {}; identity["active"]=False
capture=int(sys.argv[2])
agent=None if sys.argv[3]=="null" else int(sys.argv[3])
source=None if sys.argv[4]=="null" else json.loads(sys.argv[4])
exited_at=sys.argv[5]
contract_id=sys.argv[6]
reason=sys.argv[7]
limitations=list(state.get("lifecycle_limitations") or [])
if agent is None:
 limitations.append("Underlying Code Agent exit status was unavailable ("+reason+"); the capture-process status was preserved as capture evidence and was not relabeled as agent status.")
 detail=None
elif agent==0:
 detail="normal-zero"
elif 1<=agent<=31:
 # macOS /usr/bin/script returns a bare signal number for a signal-terminated
 # child, so a low value cannot distinguish an ordinary exit from a signal.
 # The number is preserved exactly and is never rewritten to 128+n.
 detail="ambiguous-exit-or-signal"
 limitations.append("Code Agent status "+str(agent)+" cannot distinguish an ordinary exit from termination by signal "+str(agent)+"; recorded as ambiguous-exit-or-signal without conversion.")
else:
 detail="nonzero"
print(json.dumps({"runtime_identity":identity,"agent_exited_at":exited_at,"capture_process_exit_status":capture,"code_agent_exit_status":agent,"code_agent_exit_status_available":agent is not None,"code_agent_exit_status_source":source,"capture_status_contract_id":contract_id,"termination_detail":detail,"agent_exit_code":agent,"lifecycle_limitations":limitations}))' \
    "$AI_RUNTIME_STATE_PATH" "$AI_CAPTURE_EXIT_STATUS" "$code_agent_status_json" "$status_source_json" "$AI_AGENT_EXITED_AT" "$AI_CAPTURE_STATUS_CONTRACT_ID" "${contract_reason:-contract satisfied}")" || die 90 state "cannot encode process exit evidence"
  atomic_merge "$patch"
  print -r -- "{\"recorded_at\":\"$(now)\",\"agent_exited_at\":\"$AI_AGENT_EXITED_AT\",\"capture_process_exit_status\":$AI_CAPTURE_EXIT_STATUS,\"code_agent_exit_status\":$code_agent_status_json,\"capture_status_contract_id\":\"$AI_CAPTURE_STATUS_CONTRACT_ID\"}" >| "$AI_RUNNER_CONTROL_PATH/process-exit-recorded.json" || die 90 evidence "cannot record process exit evidence"
  print -- "[$(now)] process statuses recorded; capture_exit=$AI_CAPTURE_EXIT_STATUS code_agent_exit=$code_agent_status_json contract=$AI_CAPTURE_STATUS_CONTRACT_ID agent_exited_at=$AI_AGENT_EXITED_AT" >> "$AI_META_LOG_PATH" || die 90 meta "cannot append process exit evidence"
}

complete_collector_phase() {
  [[ -s "$AI_RUNNER_CONTROL_PATH/process-exit-recorded.json" ]] || die 30 lifecycle "process completion phase has not completed"
  need AI_COLLECTOR_EXIT_STATUS
  [[ "$AI_COLLECTOR_EXIT_STATUS" == <-> && "$AI_COLLECTOR_EXIT_STATUS" -ge 0 && "$AI_COLLECTOR_EXIT_STATUS" -le 255 ]] || die 20 collector "invalid collector exit status"
  [[ -s "$AI_COLLECTOR_STATE_PATH" ]] || die 40 collector "collector state is missing"
  local diagnostics="$AI_RUNNER_CONTROL_PATH/collector-validation-errors.log" patch
  patch="$(python3 - "$AI_RUNTIME_STATE_PATH" "$AI_COLLECTOR_STATE_PATH" "$AI_COLLECTOR_EXIT_STATUS" "$AI_ARTIFACT_STEM" "$AI_RAW_LOG_PATH" "$AI_CLEAN_LOG_PATH" <<'PY' 2>>"$diagnostics"
import datetime,json,sys
runtime_path,state_path,actual_s,stem,raw,clean=sys.argv[1:]
runtime=json.load(open(runtime_path,encoding="utf-8")); state=json.load(open(state_path,encoding="utf-8")); actual=int(actual_s)
required={"workflow_version","artifact_stem","status","clean_log_ready","raw_log_path","clean_log_path","collector_exit_status","completed_at","normalization_method","failure"}
missing=sorted(required-set(state))
if missing: raise SystemExit("missing collector-state fields: "+", ".join(missing))
if state.get("workflow_version")!="v2.4.1" or state.get("artifact_stem")!=stem: raise SystemExit("collector identity mismatch")
if state.get("raw_log_path")!=raw or state.get("clean_log_path")!=clean: raise SystemExit("collector path mismatch")
if state.get("collector_exit_status")!=actual: raise SystemExit("collector exit-status mismatch")
if state.get("status")!="succeeded" or state.get("clean_log_ready") is not True or actual!=0: raise SystemExit("collector did not establish clean-log readiness")
print(json.dumps({"collector_exit_status":actual,"collector_status":"succeeded","collector_clean_log_ready":True,"collector_completed_at":state["completed_at"],"collector_state_path":state_path}))
PY
)" || die 40 collector "collector completion validation failed; diagnostics: ${diagnostics#$AI_PROJECT_ROOT/}"
  atomic_merge "$patch"
  local available
  available="$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1],encoding="utf-8")).get("code_agent_exit_status_available") is True).lower())' "$AI_RUNTIME_STATE_PATH")" || die 90 state "cannot inspect Code Agent exit availability"
  [[ "$available" == true ]] || die 40 exit "underlying Code Agent exit status is unavailable; workflow finalization is blocked"
  print -r -- "{\"completed_at\":\"$(now)\",\"collector_exit_status\":$AI_COLLECTOR_EXIT_STATUS}" >| "$AI_RUNNER_CONTROL_PATH/lifecycle-complete.json" || die 90 evidence "cannot record lifecycle completion"
  print -- "[$(now)] lifecycle evidence complete; collector_exit=$AI_COLLECTOR_EXIT_STATUS" >> "$AI_META_LOG_PATH" || die 90 meta "cannot append lifecycle completion"
}

complete_operation() {
  need AI_COMPLETE_PHASE
  case "$AI_COMPLETE_PHASE" in
    process) complete_process_phase ;;
    collector) complete_collector_phase ;;
    *) die 2 input "AI_COMPLETE_PHASE must be process or collector" ;;
  esac
}

check_common
case "${1:-}" in
  validate) validate_contract ;;
  begin) begin_boundary ;;
  register) register_process ;;
  complete) complete_operation ;;
  *) die 2 input "usage: $CLI_SCRIPT_NAME {validate|begin|register|complete}" ;;
esac
