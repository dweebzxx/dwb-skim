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
die() {
  local c="$1" s="$2" m="$3"
  if [[ -n "${AI_POST_PASS_DONE_PATH:-}" ]]; then
    mkdir -p -- "${AI_POST_PASS_DONE_PATH:h}" 2>/dev/null || true
    print -r -- failed >| "$AI_POST_PASS_DONE_PATH" 2>/dev/null || true
    if [[ -n "${AI_META_LOG_PATH:-}" ]]; then
      {
        print -- "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] post-pass failed"
        print -- "workflow_finalization_result=failed"
        print -- "failure_rule=$s"
        print -- "failure_summary=$m"
      } >> "$AI_META_LOG_PATH" 2>/dev/null || true
    fi
  fi
  err "$s" "$m"
  exit "$c"
}
need() { local n="$1"; [[ -n "${(P)n:-}" ]] || die 2 input "missing environment variable: $n"; }
need_file() { [[ -f "$1" ]] || die 10 prerequisite "$2 not found: $1"; }
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
  local diagnostics="${AI_TMP_ROOT:-${target:h}}/runtime/cli-post-pass-python-errors.log"
  mkdir -p -- "${target:h}" "${diagnostics:h}" || die 90 state "cannot create state parent: ${target:h}"
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
for n in AI_REPORT_PATH AI_METADATA_PATH AI_CONTINUATION_STATE_PATH AI_REPORT_TEMPLATE AI_METADATA_SCHEMA AI_PROMPT_PATH AI_LAUNCHER_PATH AI_POST_PASS_DONE_PATH AI_TMP_ROOT AI_OUTPUT_ROOT AI_RAW_LOG_PATH AI_CLEAN_LOG_PATH AI_COLLECTOR_CONTROL_PATH AI_COLLECTOR_STATE_PATH AI_RUNNER_CONTROL_PATH; do need "$n"; done
need_file "$AI_REPORT_PATH" "Host report"
need_file "$AI_METADATA_PATH" "provisional metadata"
need_file "$AI_REPORT_TEMPLATE" "Host report template"
need_file "$AI_METADATA_SCHEMA" "metadata schema"
need_file "$AI_PROMPT_PATH" "saved prompt"
need_file "$AI_LAUNCHER_PATH" "saved launcher"
need_file "$AI_RAW_LOG_PATH" "raw log"
need_file "$AI_RUNNER_CONTROL_PATH/lifecycle-complete.json" "runner lifecycle-complete evidence"
need_file "$AI_COLLECTOR_STATE_PATH" "collector state"
python3 -c 'import json,sys
runtime=json.load(open(sys.argv[1],encoding="utf-8")); collector=json.load(open(sys.argv[2],encoding="utf-8"))
if collector.get("workflow_version")!="v2.4.1" or collector.get("artifact_stem")!=sys.argv[3]: raise SystemExit(1)
if collector.get("status")!="succeeded" or collector.get("clean_log_ready") is not True or collector.get("collector_exit_status")!=0: raise SystemExit(1)
if collector.get("raw_log_path")!=sys.argv[4] or collector.get("clean_log_path")!=sys.argv[5]: raise SystemExit(1)
if runtime.get("collector_status")!="succeeded" or runtime.get("collector_clean_log_ready") is not True or runtime.get("collector_exit_status")!=0: raise SystemExit(1)
if runtime.get("code_agent_exit_status_available") is not True or not isinstance(runtime.get("code_agent_exit_status"),int): raise SystemExit(1)
if runtime.get("capture_process_exit_status") is None: raise SystemExit(1)
identity=runtime.get("runtime_identity")
required={"pass_id","artifact_stem","lifecycle_session_id","launcher_pid","launcher_process_start_marker","capture_pid","capture_process_start_marker","code_agent_pid","code_agent_binary","code_agent_process_start_marker","process_group_id","raw_log_path","registered_at","active"}
if not isinstance(identity,dict) or not required.issubset(identity): raise SystemExit(1)
if identity.get("active") is not False or identity.get("raw_log_path")!=sys.argv[4]: raise SystemExit(1)'   "$AI_RUNTIME_STATE_PATH" "$AI_COLLECTOR_STATE_PATH" "$AI_ARTIFACT_STEM" "$AI_RAW_LOG_PATH" "$AI_CLEAN_LOG_PATH"   || die 40 collector "clean-log readiness or lifecycle completion is invalid"
need_file "$AI_CLEAN_LOG_PATH" "clean log"
[[ "$AI_REPORT_TEMPLATE" == "$AI_PROJECT_ROOT/.dwbskim-private/workflow-templates/pass-report-template.md" ]] || die 60 report-template "Host report template must be .dwbskim-private/workflow-templates/pass-report-template.md"
inside "$AI_TMP_ROOT" "$AI_REPORT_ROOT"
inside "$AI_OUTPUT_ROOT" "$AI_REPORT_ROOT"
inside "$AI_REPORT_PATH" "$AI_REPORT_ROOT"
inside "$AI_METADATA_PATH" "$AI_REPORT_ROOT"
inside "$AI_CONTINUATION_STATE_PATH" "$AI_REPORT_ROOT"
inside "$AI_COLLECTOR_CONTROL_PATH" "$AI_REPORT_ROOT"
inside "$AI_COLLECTOR_STATE_PATH" "$AI_REPORT_ROOT"
inside "$AI_RUNNER_CONTROL_PATH" "$AI_REPORT_ROOT"

[[ "$AI_PROMPT_PATH" == "$AI_REPORT_ROOT/prompts/${AI_ARTIFACT_STEM}-prompt.txt" ]] \
  || die 20 path "prompt path does not match the canonical artifact path"

[[ "$AI_LAUNCHER_PATH" == "$AI_REPORT_ROOT/launchers/${AI_ARTIFACT_STEM}-launcher.zsh" ]] \
  || die 20 path "launcher path does not match the canonical artifact path"

[[ "$AI_REPORT_PATH" == "$AI_REPORT_ROOT/reports/${AI_ARTIFACT_STEM}-report.md" ]] \
  || die 20 path "report path does not match the canonical artifact path"

[[ "$AI_METADATA_PATH" == "$AI_REPORT_ROOT/metadata-reports/${AI_ARTIFACT_STEM}-metadata.json" ]] \
  || die 20 path "metadata path does not match the canonical artifact path"

[[ "$AI_CONTINUATION_STATE_PATH" == "$AI_REPORT_ROOT/metadata-reports/${AI_ARTIFACT_STEM}-continuation-state.json" ]] \
  || die 20 path "continuation-state path does not match the canonical artifact path"

[[ "$AI_RAW_LOG_PATH" == "$AI_REPORT_ROOT/logs/raw-logs/${AI_ARTIFACT_STEM}-raw.log" ]] \
  || die 20 path "raw-log path does not match the canonical artifact path"

[[ "$AI_CLEAN_LOG_PATH" == "$AI_REPORT_ROOT/logs/clean-logs/${AI_ARTIFACT_STEM}-clean.log" ]] \
  || die 20 path "clean-log path does not match the canonical artifact path"

[[ "$AI_META_LOG_PATH" == "$AI_REPORT_ROOT/logs/meta-logs/${AI_ARTIFACT_STEM}-meta.log" ]] \
  || die 20 path "meta-log path does not match the canonical artifact path"

[[ "$AI_METADATA_SCHEMA" == "$AI_PROJECT_ROOT/.dwbskim-private/metadata-schema.json" ]] \
  || die 20 path "metadata schema path must be .dwbskim-private/metadata-schema.json"

[[ "$AI_TMP_ROOT" == "$AI_REPORT_ROOT/tmp/$AI_ARTIFACT_STEM" ]] \
  || die 20 path "temporary root does not match the canonical artifact path"

[[ "$AI_OUTPUT_ROOT" == "$AI_REPORT_ROOT/outputs/$AI_ARTIFACT_STEM" ]] \
  || die 20 path "output root does not match the canonical artifact path"

[[ "$AI_RUNTIME_STATE_PATH" == "$AI_TMP_ROOT/runtime/launcher-state.json" ]] \
  || die 20 path "runtime-state path does not match the canonical artifact path"

local diagnostics="$AI_TMP_ROOT/runtime/post-pass-python-errors.log"
mkdir -p -- "$AI_TMP_ROOT/runtime" || die 90 runtime "cannot create post-pass runtime directory"

local pub_start="$AI_TMP_ROOT/runtime/public-start.json"
local priv_start="$AI_TMP_ROOT/runtime/private-start.json"
local protected_start="$AI_TMP_ROOT/runtime/protected-workflow-start.json"
need_file "$pub_start" "starting public repository snapshot"
need_file "$priv_start" "starting private repository snapshot"
need_file "$protected_start" "starting protected-workflow snapshot"

local pub="$AI_TMP_ROOT/runtime/public-end.json"
local priv="$AI_TMP_ROOT/runtime/private-end.json"
local protected_end="$AI_TMP_ROOT/runtime/protected-workflow-end.json"

python3 -c 'import hashlib,json,os,subprocess,sys,tempfile

def signature(repo,path):
 full=os.path.join(repo,path)
 try: os.lstat(full)
 except FileNotFoundError:
  cp=subprocess.run(["git","-C",repo,"rev-parse",f"HEAD:{path}"],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
  return "git-object:"+cp.stdout.strip() if cp.returncode==0 and cp.stdout.strip() else None
 if os.path.islink(full): return "symlink-sha256:"+hashlib.sha256(os.readlink(full).encode("utf-8","surrogateescape")).hexdigest()
 if os.path.isfile(full):
  h=hashlib.sha256()
  with open(full,"rb") as f:
   for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
  return "sha256:"+h.hexdigest()
 return None

def snap(repo,label):
 if not os.path.isdir(os.path.join(repo,".git")): return {"repository":label,"present":False,"head":None,"branch":None,"entries":[]}
 cp=subprocess.run(["git","-C",repo,"status","--porcelain=v1","-z","--untracked-files=all"],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if cp.returncode: raise RuntimeError(cp.stderr.decode(errors="replace"))
 records=cp.stdout.split(b"\0"); out=[]; i=0
 while i < len(records):
  rec=records[i]; i+=1
  if not rec: continue
  text=rec.decode("utf-8","surrogateescape"); status=text[:2]; path=text[3:]; original=None
  if "R" in status or "C" in status:
   if i < len(records) and records[i]: original=records[i].decode("utf-8","surrogateescape"); i+=1
  if path==".DS_Store" or path.endswith("/.DS_Store"): continue
  sig=signature(repo,path)
  out.append({"repository":label,"status":status,"status_type":status,"path":path,"original_path":original,"signature":sig,"content_signature":sig,"classification":"inherited","ignored_noise":False})
 head=subprocess.run(["git","-C",repo,"rev-parse","HEAD"],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 branch=subprocess.run(["git","-C",repo,"branch","--show-current"],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 return {"repository":label,"present":True,"head":head.stdout.strip() if head.returncode==0 else None,"branch":branch.stdout.strip() if branch.returncode==0 else None,"entries":sorted(out,key=lambda x:(x["path"],x["status"],x.get("original_path") or ""))}

def save(path,obj):
 os.makedirs(os.path.dirname(path),exist_ok=True); fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),prefix=".tmp-",text=True)
 with os.fdopen(fd,"w",encoding="utf-8") as f: json.dump(obj,f,indent=2,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno())
 os.replace(tmp,path)

def path_state(root,rel):
 full=os.path.join(root,rel)
 try: os.lstat(full)
 except FileNotFoundError: return {"path":rel,"type":"absent","signature":None}
 if os.path.islink(full):
  target=os.readlink(full); return {"path":rel,"type":"symlink","target":target,"signature":"symlink-sha256:"+hashlib.sha256(target.encode()).hexdigest()}
 if os.path.isfile(full):
  h=hashlib.sha256()
  with open(full,"rb") as f:
   for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
  return {"path":rel,"type":"file","signature":"sha256:"+h.hexdigest()}
 if os.path.isdir(full):
  h=hashlib.sha256()
  for base,dirs,files in os.walk(full,followlinks=False):
   dirs.sort(); files.sort()
   for name in dirs+files:
    p=os.path.join(base,name); r=os.path.relpath(p,full); h.update(r.encode("utf-8","surrogateescape")+b"\0")
    if os.path.islink(p): h.update(b"L\0"+os.readlink(p).encode("utf-8","surrogateescape"))
    elif os.path.isfile(p):
     h.update(b"F\0")
     with open(p,"rb") as f:
      for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
    else: h.update(b"D\0")
  return {"path":rel,"type":"directory","signature":"tree-sha256:"+h.hexdigest()}
 return {"path":rel,"type":"other","signature":None}

root=sys.argv[1]
save(sys.argv[2],snap(root,"project")); save(sys.argv[3],snap(os.path.join(root,".dwbskim-private"),"private"))
protected=["AGENTS.md","CLAUDE.md","metadata-schema.json","skills-lock.json",".agents",".claude/skills"]
protected += ["scripts"] if os.path.islink(os.path.join(root,"scripts")) else ["scripts/cli-initialize.zsh","scripts/cli-pre-pass.zsh","scripts/cli-agent-runner.zsh","scripts/cli-post-pass.zsh","scripts/cli-log-collector.zsh","scripts/cli-commit.zsh","scripts/cli-push.zsh","scripts/cli-session-abort.zsh"]
private=[".dwbskim-private/AGENTS.md",".dwbskim-private/metadata-schema.json",".dwbskim-private/skills-lock.json",".dwbskim-private/workflow-templates/pass-report-template.md",".dwbskim-private/.agents/skills",".dwbskim-private/.agents/skills-store",".dwbskim-private/scripts"]
save(sys.argv[4],{"paths":[path_state(root,p) for p in protected+private]})' \
  "$AI_PROJECT_ROOT" "$pub" "$priv" "$protected_end" 2>>"$diagnostics" \
  || die 30 repository-state "cannot capture ending repository/control state; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"

local inherited_manifest="$AI_TMP_ROOT/runtime/inherited-changes.json"
local pass_manifest="$AI_TMP_ROOT/runtime/pass-produced-changes.json"
local workflow_manifest="$AI_TMP_ROOT/runtime/workflow-files-modified.json"
local scope_diagnostics="$AI_TMP_ROOT/runtime/write-scope-diagnostics.json"

python3 -c 'import json,os,sys,tempfile

def load(path):
 with open(path,encoding="utf-8") as f: return json.load(f)
def save(path,obj):
 os.makedirs(os.path.dirname(path),exist_ok=True); fd,tmp=tempfile.mkstemp(prefix=".tmp-",dir=os.path.dirname(path),text=True)
 with os.fdopen(fd,"w",encoding="utf-8") as f: json.dump(obj,f,indent=2,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno())
 os.replace(tmp,path)
def key(entry): return (entry.get("status"),entry.get("path"),entry.get("signature"),entry.get("original_path"))
def normalize(path):
 value=os.path.normpath(path.replace("\\","/"))
 if value in ("",".","..") or value.startswith("../") or os.path.isabs(value): raise ValueError(path)
 return value

start={"project":load(sys.argv[1]),"private":load(sys.argv[2])}
end={"project":load(sys.argv[3]),"private":load(sys.argv[4])}
protected_start={x["path"]:x for x in load(sys.argv[5]).get("paths",[])}
protected_end={x["path"]:x for x in load(sys.argv[6]).get("paths",[])}
scripts_variant={"scripts"}|{"scripts/cli-"+n+".zsh" for n in ("initialize","pre-pass","agent-runner","post-pass","log-collector","commit","push","session-abort")}
drifted=sorted((set(protected_start)^set(protected_end))-scripts_variant)
if drifted:
 raise SystemExit("protected-path list disagrees between cli-pre-pass.zsh and cli-post-pass.zsh; the two copies have drifted: "+", ".join(drifted))
pass_type=sys.argv[7]; auth_path=sys.argv[8]
inherited=[]; produced=[]
for repo in ("project","private"):
 sm={x.get("path"):x for x in start[repo].get("entries",[])}
 em={x.get("path"):x for x in end[repo].get("entries",[])}
 for path in sorted(set(sm)|set(em)):
  before=sm.get(path); after=em.get(path)
  if before is not None and after is not None and key(before)==key(after):
   after["classification"]="inherited"; inherited.append(after)
  else:
   if after is not None: after["classification"]="pass-produced"
   produced.append({"repository":repo,"path":path,"classification":"pass-produced","before":before,"after":after})
 save(sys.argv[3] if repo=="project" else sys.argv[4],end[repo])
workflow=[]
for path in sorted(set(protected_start)|set(protected_end)):
 before=protected_start.get(path); after=protected_end.get(path)
 if before!=after:
  repo="private" if path.startswith(".dwbskim-private/") else "project"
  rel=path[len(".dwbskim-private/"):] if repo=="private" else path
  workflow.append({"repository":repo,"path":rel,"before":before,"after":after})
allowed=[]
if auth_path:
 with open(auth_path,encoding="utf-8") as f:
  for lineno,line in enumerate(f,1):
   line=line.rstrip("\n")
   if not line or line.lstrip().startswith("#"): continue
   parts=line.split("\t",1)
   if len(parts)!=2 or parts[0] not in ("project","private"): raise RuntimeError(f"invalid authorization manifest line {lineno}")
   raw=parts[1]; prefix=raw.endswith("/"); value=normalize(raw[:-1] if prefix else raw)
   allowed.append((parts[0],value,prefix))
def permitted(repo,path):
 path=normalize(path)
 return any(r==repo and (path==base or (prefix and path.startswith(base+"/"))) for r,base,prefix in allowed)
implementation_private_allowed={
 normalize(sys.argv[13]),
 normalize(sys.argv[14]),
}

unauthorized=[]
if pass_type=="implementation":
 unauthorized.extend([
  x for x in produced
  if x["repository"]=="private"
  and normalize(x["path"]) not in implementation_private_allowed
 ])
 unauthorized.extend(workflow)
elif pass_type in ("bootstrap","adoption","maintenance","skill_bootstrap"):
 if (produced or workflow) and not auth_path:
  unauthorized.append({"rule":"authorized-write-manifest-required","pass_type":pass_type})
 else:
  unauthorized.extend([x for x in produced if not permitted(x["repository"],x["path"])])
  unauthorized.extend([x for x in workflow if not permitted(x["repository"],x["path"])])
else:
 unauthorized.append({"rule":"unsupported-pass-type","pass_type":pass_type})
save(sys.argv[9],{"changes":inherited}); save(sys.argv[10],{"changes":produced}); save(sys.argv[11],{"changes":workflow}); save(sys.argv[12],{"unauthorized":unauthorized})
raise SystemExit(1 if unauthorized else 0)' \
  "$pub_start" "$priv_start" "$pub" "$priv" "$protected_start" "$protected_end" "$AI_PASS_TYPE" "${AI_AUTHORIZED_WRITE_MANIFEST_PATH:-}" \
  "$inherited_manifest" "$pass_manifest" "$workflow_manifest" "$scope_diagnostics" \
  "build-report-logs/reports/${AI_ARTIFACT_STEM}-report.md" \
  "build-report-logs/metadata-reports/${AI_ARTIFACT_STEM}-metadata.json" 2>>"$diagnostics" \
  || die 60 write-scope "unauthorized pass-local changes recorded at ${scope_diagnostics#$AI_PROJECT_ROOT/}"

local agent_exit product

agent_exit="$(python3 -c 'import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8")).get("code_agent_exit_status","null"))' \
  "$AI_RUNTIME_STATE_PATH" 2>>"$diagnostics")" \
  || die 90 telemetry "cannot read agent exit telemetry; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"

# ---------------------------------------------------------------------------
# Provider telemetry parser (Host Guide 8.4, 15.4).
#
# Invoked here and only here: after collector clean-ready evidence has been
# validated above, and before any metadata or report validation below. The
# parser is a tool, not a Host script; it is never given a Code Agent binary or
# prompt content, and it is invoked with a structured argument list rather than
# a reconstructed shell command.
# ---------------------------------------------------------------------------
local telemetry_result="${AI_NORMALIZED_TELEMETRY_PATH:-$AI_TMP_ROOT/runtime/provider-telemetry.json}"
local parser_tool="${AI_PROVIDER_TELEMETRY_TOOL_PATH:-$AI_PROJECT_ROOT/tools/provider_telemetry_extract-v2.4.1.py}"
local parser_fixtures="${AI_PROVIDER_TELEMETRY_FIXTURES_PATH:-$AI_PROJECT_ROOT/tools/provider_telemetry_fixtures-v2.4.1.json}"
local parser_diagnostics="$AI_TMP_ROOT/runtime/provider-telemetry-errors.log"

inside "$telemetry_result" "$AI_TMP_ROOT"
[[ -r "$parser_tool" ]] \
  || die 10 prerequisite "provider telemetry parser is absent or unreadable: ${parser_tool#$AI_PROJECT_ROOT/}"
[[ -r "$parser_fixtures" ]] \
  || die 10 prerequisite "provider telemetry fixture catalog is absent or unreadable: ${parser_fixtures#$AI_PROJECT_ROOT/}"

python3 "$parser_tool" \
  --pass-id "$AI_PASS_ID" \
  --stem "$AI_ARTIFACT_STEM" \
  --code-agent "$AI_CODE_AGENT" \
  --clean-log "$AI_CLEAN_LOG_PATH" \
  --raw-log "$AI_RAW_LOG_PATH" \
  --fixtures "$parser_fixtures" \
  --output "$telemetry_result" \
  --project-root "$AI_PROJECT_ROOT" 2>>"$parser_diagnostics" \
  || die 60 telemetry "provider telemetry parser failed; diagnostics retained at ${parser_diagnostics#$AI_PROJECT_ROOT/}"

# The parser result is validated before any value is copied out of it. A valid
# result whose optional values are null is accepted and finalization continues;
# a malformed, contradictory, wrong-identity, or path-escaping result is fatal.
local telemetry_json
telemetry_json="$(python3 - "$telemetry_result" "$AI_PASS_ID" "$AI_ARTIFACT_STEM" "$AI_PROJECT_ROOT" "$AI_CLEAN_LOG_PATH" "$AI_RAW_LOG_PATH" <<'PY' 2>>"$parser_diagnostics"
import json, os, sys
result_path, pass_id, stem, project_root, clean_log, raw_log = sys.argv[1:7]
with open(result_path, encoding="utf-8") as handle:
    result = json.load(handle)
if not isinstance(result, dict):
    raise SystemExit("provider telemetry result root must be an object")
required = {"workflow_version", "parser_contract", "pass_id", "artifact_stem",
            "code_agent", "clean_log_path", "raw_log_path", "captured_at",
            "legacy_total_tokens", "legacy_total_source", "telemetry",
            "session", "field_sources", "completeness", "limitations"}
missing = sorted(required - set(result))
if missing:
    raise SystemExit("missing provider telemetry fields: " + ", ".join(missing))
if result["workflow_version"] != "v2.4.1":
    raise SystemExit("provider telemetry workflow_version mismatch")
if result["parser_contract"] != "provider-telemetry-v1":
    raise SystemExit("unsupported parser contract: " + str(result["parser_contract"]))
if result["pass_id"] != pass_id or result["artifact_stem"] != stem:
    raise SystemExit("provider telemetry identity does not match this pass")
for key, expected in (("clean_log_path", clean_log), ("raw_log_path", raw_log)):
    observed = result[key]
    absolute = observed if os.path.isabs(observed) else os.path.join(project_root, observed)
    if os.path.realpath(absolute) != os.path.realpath(expected):
        raise SystemExit("provider telemetry " + key + " does not match this pass")
    if ".." in str(observed).split("/"):
        raise SystemExit("provider telemetry " + key + " escapes the project root")
telemetry = result["telemetry"]
if not isinstance(telemetry, dict):
    raise SystemExit("provider telemetry.telemetry must be an object")
for field in ("total_tokens", "input_tokens", "cached_input_tokens",
              "output_tokens", "reasoning_tokens"):
    value = telemetry.get(field)
    if value is not None and (not isinstance(value, int) or isinstance(value, bool) or value < 0):
        raise SystemExit("provider telemetry " + field + " must be a non-negative integer or null")
session = result["session"]
if not isinstance(session, dict):
    raise SystemExit("provider telemetry.session must be an object")
for field in ("session_id", "conversation_id", "session_slug", "resume_command"):
    value = session.get(field)
    if value is not None and (not isinstance(value, str) or not value):
        raise SystemExit("provider telemetry " + field + " must be a nonempty string or null")
legacy = result["legacy_total_tokens"]
if legacy is not None and (not isinstance(legacy, int) or isinstance(legacy, bool) or legacy < 0):
    raise SystemExit("legacy_total_tokens must be a non-negative integer or null")
if result["completeness"] not in ("complete", "partial", "unavailable"):
    raise SystemExit("invalid telemetry completeness: " + str(result["completeness"]))
limitations = result["limitations"]
if not isinstance(limitations, list) or not all(isinstance(x, str) and x for x in limitations):
    raise SystemExit("telemetry limitations must be an array of nonempty strings")
scopes = result.get("scopes") or {}
legacy_scope = scopes.get("legacy_total", "unknown")
verified_scope = scopes.get("verified_total", "unknown")
if legacy_scope not in ("cumulative-session", "unknown"):
    raise SystemExit("invalid legacy total scope: " + str(legacy_scope))
if verified_scope not in ("cumulative-session", "last-request", "current-context", "unknown"):
    raise SystemExit("invalid verified total scope: " + str(verified_scope))
# A verified cumulative total is never asserted without a labelled source.
if telemetry.get("total_tokens") is not None and verified_scope == "unknown":
    raise SystemExit("verified total present with unknown scope; a labelled provider source is required")
print(json.dumps({
    "legacy_total_tokens": legacy,
    "telemetry": {
        "total_tokens": telemetry.get("total_tokens"),
        "input_tokens": telemetry.get("input_tokens"),
        "cached_input_tokens": telemetry.get("cached_input_tokens"),
        "output_tokens": telemetry.get("output_tokens"),
        "reasoning_tokens": telemetry.get("reasoning_tokens"),
        "legacy_total_scope": legacy_scope,
        "verified_total_scope": verified_scope,
        "completeness": result["completeness"],
        "parser_contract": "provider-telemetry-v1",
        "limitations": sorted(set(limitations)),
    },
    "session": {
        "session_id": session.get("session_id"),
        "conversation_id": session.get("conversation_id"),
        "session_slug": session.get("session_slug"),
        "resume_command": session.get("resume_command"),
    },
}))
PY
)" \
  || die 60 telemetry "provider telemetry result is invalid; diagnostics retained at ${parser_diagnostics#$AI_PROJECT_ROOT/}"

product="$(python3 -c 'import json,sys
value=json.load(open(sys.argv[1],encoding="utf-8")).get("product_result")
allowed={"succeeded","failed","partial","not-run","unknown"}
if value not in allowed:
 raise SystemExit("provisional metadata contains an invalid or missing product_result")
print(value)' \
  "$AI_METADATA_PATH" 2>>"$diagnostics")" \
  || die 60 metadata "cannot preserve the Code Agent-authored product result; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"

local metadata_tmp="${AI_METADATA_PATH:h}/.${AI_METADATA_PATH:t}.tmp.$$"
local continuation_tmp="${AI_CONTINUATION_STATE_PATH:h}/.${AI_CONTINUATION_STATE_PATH:t}.tmp.$$"
local diagnostics="$AI_TMP_ROOT/runtime/post-pass-python-errors.log"

python3 -c 'import json,sys,os,datetime
src,dst=sys.argv[1],sys.argv[2]
data=json.load(open(src,encoding="utf-8"))

# Canonicalize the known nonstandard-output alias before schema validation.
artifacts=data.get("artifacts")
if not isinstance(artifacts,dict):
 raise SystemExit("provisional metadata artifacts must be an object")

legacy_nonstandard=data.pop("nonstandard_deliverables",None)

if "nonstandard_outputs" not in artifacts:
 if legacy_nonstandard is None:
  artifacts["nonstandard_outputs"]=[]
 elif isinstance(legacy_nonstandard,list):
  artifacts["nonstandard_outputs"]=legacy_nonstandard
 else:
  raise SystemExit("nonstandard_deliverables must be an array when present")
elif legacy_nonstandard is not None and legacy_nonstandard != artifacts["nonstandard_outputs"]:
 raise SystemExit("conflicting nonstandard_deliverables and artifacts.nonstandard_outputs values")

data["workflow_version"]="v2.4.1"
data["product_result"]=sys.argv[3]
data["agent_exit_code"]=None if sys.argv[4]=="null" else int(sys.argv[4])
data.pop("finalized",None)
data["workflow_finalization_result"]="succeeded"
data["finalized_at"]=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# compact-final-v1 and full-provisional-v1 both drop the nine flat token and
# session mirrors; their canonical values live in the grouped telemetry and
# session objects (Host Guide 8.13).
for key in (
 "tokens_total",
 "tokens_input",
 "tokens_cached_input",
 "tokens_output",
 "tokens_reasoning",
 "session_id",
 "conversation_id",
 "session_slug",
 "resume_command",
 "telemetry_limitations",
 "exit_status_agreement"
):
 data.pop(key,None)

# Post-pass owns the format version; a Code Agent-supplied value is not
# trusted, because the version is the schema branch discriminator.
data["metadata_format_version"]="full-provisional-v1"
data["metadata_finalized"]=False

with open(dst,"w",encoding="utf-8") as f:
 json.dump(data,f,indent=2,sort_keys=True)
 f.write("\n")
 f.flush()
 os.fsync(f.fileno())' \
  "$AI_METADATA_PATH" "$metadata_tmp" "$product" "$agent_exit" 2>"$diagnostics" \
  || {
    rm -f -- "$metadata_tmp" "$continuation_tmp" 2>/dev/null || true
    die 60 metadata "cannot build enriched metadata; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"
  }

local metadata_enriched="${metadata_tmp}.enriched"
python3 -c 'import datetime,json,os,sys

def load(path):
 with open(path,encoding="utf-8") as f: return json.load(f)
data=load(sys.argv[1]); runtime=load(sys.argv[2])
start={"project":load(sys.argv[3]),"private":load(sys.argv[4])}
end={"project":load(sys.argv[5]),"private":load(sys.argv[6])}
inherited=load(sys.argv[7]).get("changes",[])
produced=load(sys.argv[8]).get("changes",[])
workflow=load(sys.argv[9]).get("changes",[])
# Telemetry and session come from the validated provider-telemetry result and
# from nowhere else. There is no fallback to Code Agent-authored values: a
# field the parser could not establish stays null (Host Guide 8.4).
parsed=json.loads(sys.argv[11])
data["telemetry"]=parsed["telemetry"]
data["session"]=parsed["session"]
data["total_tokens_used"]=parsed["legacy_total_tokens"]
started=runtime.get("agent_started_at"); exited=runtime.get("agent_exited_at"); duration=None
try:
 if started and exited:
  a=datetime.datetime.fromisoformat(started.replace("Z","+00:00")); b=datetime.datetime.fromisoformat(exited.replace("Z","+00:00")); duration=max(0,int((b-a).total_seconds()))
except Exception: duration=None
data["duration_seconds"]=duration
data["agent_started"]=runtime.get("agent_started") is True
data["agent_started_at"]=runtime.get("agent_started_at")
data["agent_exited_at"]=runtime.get("agent_exited_at")
data["runtime_identity"]=runtime.get("runtime_identity")
data["capture_process_exit_status"]=runtime.get("capture_process_exit_status")
data["code_agent_exit_status"]=runtime.get("code_agent_exit_status")
data["code_agent_exit_status_available"]=runtime.get("code_agent_exit_status_available") is True
data["agent_exit_code"]=runtime.get("code_agent_exit_status")
data["collector_exit_status"]=runtime.get("collector_exit_status")
data["collector_status"]=runtime.get("collector_status")
data["collector_clean_log_ready"]=runtime.get("collector_clean_log_ready") is True
data["collector_completed_at"]=runtime.get("collector_completed_at")
# Status provenance replaces the removed agreement flag. Propagated equality is
# one accepted source, never independent corroboration (Host Guide 11.5).
data["code_agent_exit_status_source"]=runtime.get("code_agent_exit_status_source")
data["capture_status_contract_id"]=runtime.get("capture_status_contract_id")
data["termination_detail"]=runtime.get("termination_detail")
data["invocation_mode"]="direct-interactive-launcher"
data["starting_repository_state"]=start
data["ending_repository_state"]=end
data["inherited_changes"]=inherited
data["pass_produced_changes"]=produced
data["workflow_files_modified"]=workflow
data["continuation_state_finalized"]=True
# The record stays provisional through enrichment and schema validation. It
# becomes compact-final-v1 only in the compaction step below, after the
# detailed evidence has been preserved (Host Guide 8.13 finalization order).
data["metadata_format_version"]="full-provisional-v1"
data["metadata_finalized"]=False
data["report_valid"]=True
data["metadata_schema_valid"]=True
data["archive_eligible"]=True
data["metadata_evidence_index_path"]=None
data["metadata_evidence_index_sha256"]=None
data["post_pass_completed_at"]=datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(sys.argv[10],"w",encoding="utf-8") as f:
 json.dump(data,f,indent=2,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno())' \
  "$metadata_tmp" "$AI_RUNTIME_STATE_PATH" "$pub_start" "$priv_start" "$pub" "$priv" "$inherited_manifest" "$pass_manifest" "$workflow_manifest" "$metadata_enriched" "$telemetry_json" 2>>"$diagnostics" \
  || {
    rm -f -- "$metadata_tmp" "$metadata_enriched" "$continuation_tmp" 2>/dev/null || true
    die 60 metadata "cannot complete metadata enrichment; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"
  }
mv -f -- "$metadata_enriched" "$metadata_tmp" || die 60 metadata "cannot atomically install enriched metadata candidate"

python3 - "$metadata_tmp" "$AI_METADATA_SCHEMA" provisional_metadata_full_v1 <<'PY' 2>"$diagnostics" || { rm -f -- "$metadata_tmp" "$continuation_tmp" 2>/dev/null || true; die 60 metadata "provisional metadata failed schema validation: $AI_METADATA_PATH"; }
import json, sys
try:
    import jsonschema
except Exception:
    raise SystemExit("jsonschema package unavailable")
instance_path, schema_path, branch = sys.argv[1:4]
with open(instance_path, encoding="utf-8") as handle:
    instance = json.load(handle)
with open(schema_path, encoding="utf-8") as handle:
    schema = json.load(handle)
# The schema's $id is a URN, and a URN cannot serve as a resolution base for
# relative "#/definitions/..." references. Without an explicit empty base URI,
# jsonschema raises RefResolutionError on every record that reaches a $ref.
resolver = jsonschema.RefResolver(base_uri="", referrer=schema)
target = dict(schema["definitions"][branch])
target["definitions"] = schema["definitions"]
jsonschema.Draft7Validator(target, resolver=resolver).validate(instance)
PY

python3 -c 'import json,sys,datetime

runtime=json.load(open(sys.argv[1],encoding="utf-8"))
project=json.load(open(sys.argv[2],encoding="utf-8"))
private=json.load(open(sys.argv[3],encoding="utf-8"))
metadata=json.load(open(sys.argv[4],encoding="utf-8"))

def continuation_repository(snapshot):
 entries=[]
 for entry in snapshot.get("entries",[]):
  entries.append({
   "status_type":entry.get("status_type") or entry.get("status"),
   "path":entry.get("path"),
   "content_signature":entry.get("content_signature") or entry.get("signature"),
   "classification":entry.get("classification"),
   "ignored_noise":bool(entry.get("ignored_noise",False))
  })
 return {
  "repository":snapshot.get("repository"),
  "entries":entries
 }

out={
 "workflow_version":"v2.4.1",
 "pass_id":metadata.get("pass_id") or runtime.get("pass_id"),
 "artifact_stem":metadata.get("artifact_stem") or runtime.get("artifact_stem"),
 "finalized_at":metadata.get("finalized_at") or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
 "agent_started":runtime.get("agent_started") is True,
 "runtime_identity":runtime.get("runtime_identity"),
 "capture_process_exit_status":runtime.get("capture_process_exit_status"),
 "code_agent_exit_status":runtime.get("code_agent_exit_status"),
 "collector_exit_status":runtime.get("collector_exit_status"),
 "collector_status":runtime.get("collector_status"),
 "collector_clean_log_ready":runtime.get("collector_clean_log_ready") is True,
 "workflow_finalization_result":"succeeded",
 "repositories":[
  continuation_repository(project),
  continuation_repository(private)
 ]
}

with open(sys.argv[5],"w",encoding="utf-8") as f:
 json.dump(out,f,indent=2,sort_keys=True)
 f.write("\n")
 f.flush()
 import os
 os.fsync(f.fileno())' \
  "$AI_RUNTIME_STATE_PATH" \
  "$pub" \
  "$priv" \
  "$metadata_tmp" \
  "$continuation_tmp" \
  2>"$diagnostics" \
  || {
    rm -f -- "$metadata_tmp" "$continuation_tmp" 2>/dev/null || true
    die 60 continuation "cannot build continuation state: $AI_CONTINUATION_STATE_PATH; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"
  }

python3 -c 'import json,sys
try:
 import jsonschema
except Exception:
 raise SystemExit("jsonschema package unavailable")

with open(sys.argv[1],encoding="utf-8") as f:
 instance=json.load(f)

with open(sys.argv[2],encoding="utf-8") as f:
 schema_root=json.load(f)

continuation_schema=(schema_root.get("definitions") or {}).get("continuation_state")
if not isinstance(continuation_schema,dict):
 raise SystemExit("metadata schema lacks definitions.continuation_state")

jsonschema.Draft7Validator.check_schema(continuation_schema)
jsonschema.validate(instance=instance,schema=continuation_schema)' \
  "$continuation_tmp" \
  "$AI_METADATA_SCHEMA" \
  2>"$diagnostics" \
  || {
    rm -f -- "$metadata_tmp" "$continuation_tmp" 2>/dev/null || true
    die 60 continuation "continuation-state candidate failed schema validation: $AI_CONTINUATION_STATE_PATH; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"
  }

python3 -c 'import json,re,sys
report_path,template_path,metadata_path,pass_id,stem=sys.argv[1:6]
report=open(report_path,encoding="utf-8").read(); template=open(template_path,encoding="utf-8").read(); metadata=json.load(open(metadata_path,encoding="utf-8"))
if report.startswith("# Host Pass Report — "+stem+"\n") is False: raise SystemExit("report title does not match artifact stem")
unresolved={p for p in re.findall(r"<[^>\n]+>",template) if p in report}
unresolved|=set(re.findall(r"<[a-z][a-z0-9]*(?:-[a-z0-9]+)+>",report))
if unresolved: raise SystemExit("report contains unresolved placeholder: "+", ".join(sorted(unresolved)[:3]))
if "file://" in report: raise SystemExit("report contains prohibited absolute file link")
if "Audit Handoff Snapshot" in report or "Audit Pass Report" in report: raise SystemExit("report contains audit-specific template content")
required=re.findall(r"^##\s+(.+)$",template,re.M)
actual=re.findall(r"^##\s+(.+)$",report,re.M)
positions=[]
for heading in required:
 try: positions.append(actual.index(heading))
 except ValueError: raise SystemExit("missing required heading: "+heading)
if positions!=sorted(positions) or len(set(positions))!=len(positions): raise SystemExit("required heading order is invalid")
if not actual or actual[-1]!="Pass Execution Snapshot": raise SystemExit("Pass Execution Snapshot must be terminal")

def table_after(marker,text):
 pos=text.find(marker)
 if pos<0: raise SystemExit("missing table: "+marker)
 lines=text[pos:].splitlines()[1:]
 rows=[]; started=False
 for line in lines:
  if line.startswith("## ") and started: break
  if line.startswith("|"):
   started=True; cells=[c.strip() for c in line.strip().strip("|").split("|")]
   if len(cells)>=2 and cells[0] not in ("---","Identity Field","Item","Field"): rows.append((cells[0],cells[1]))
  elif started and line.strip(): break
 return rows
identity=table_after("# Host Pass Report — "+stem,report)
workflow=table_after("## Workflow State",report)
snapshot=table_after("## Pass Execution Snapshot",report)
identity_map=dict(identity); snapshot_map=dict(snapshot)
identity_order=["Pass ID","Pass Name","Pass Type","Date","Status","Product Result","Workflow Finalization Result","Workflow Guide Version","Code Agent","Model","Effort","Pass Duration","Total Tokens Used","Verified Total Tokens","Token Source and Scope","Input Tokens","Cached Input Tokens","Output Tokens","Reasoning Tokens","Token Completeness","Session or Conversation ID","Session Resume Command","Artifact Stem","Project","Project Root"]
if [k for k,v in identity]!=identity_order: raise SystemExit("identity table rows or order are invalid")
workflow_order=["Workflow guide version","AGENTS.md present at project root","AGENTS.md authorized","AGENTS.md and CLAUDE.md resolve to one inode in .dwbskim-private/","metadata-schema.json present",".dwbskim-private/ initialized",".gitignore covers private workflow controls","Prompt saved","Launcher saved","Next prompt template","Bootstrap or adoption state","AGENTS.md maintenance score"]
if [k for k,v in workflow]!=workflow_order: raise SystemExit("Workflow State rows or order are invalid")
if dict(workflow).get("Workflow guide version")!="v2.4.1": raise SystemExit("Workflow State version must be v2.4.1")
if dict(workflow).get("Prompt saved")!="yes" or dict(workflow).get("Launcher saved")!="yes": raise SystemExit("Workflow State must confirm prompt and launcher")
product_map={"success":"succeeded","failure":"failed","succeeded":"succeeded","failed":"failed","partial":"partial","not-run":"not-run","unknown":"unknown"}
workflow_map={"success":"succeeded","failure":"failed","succeeded":"succeeded","failed":"failed"}
tele=metadata.get("telemetry") or {}; session=metadata.get("session") or {}
def value(v): return "null" if v is None else str(v).lower() if isinstance(v,bool) else str(v)
checks={
 "Pass ID":metadata.get("pass_id") or pass_id,
 "Pass Type":metadata.get("pass_type"),
 "Product Result":product_map.get(metadata.get("product_result"),metadata.get("product_result")),
 "Workflow Finalization Result":workflow_map.get(metadata.get("workflow_finalization_result"),metadata.get("workflow_finalization_result")),
 "Workflow Guide Version":metadata.get("workflow_version"),
 "Code Agent":metadata.get("code_agent"),
 "Model":metadata.get("model"),
 "Effort":metadata.get("effort"),
 "Pass Duration":metadata.get("duration_seconds"),
 "Total Tokens Used":metadata.get("total_tokens_used"),
 "Verified Total Tokens":tele.get("total_tokens"),
 "Input Tokens":tele.get("input_tokens"),
 "Cached Input Tokens":tele.get("cached_input_tokens"),
 "Output Tokens":tele.get("output_tokens"),
 "Reasoning Tokens":tele.get("reasoning_tokens"),
 "Token Completeness":tele.get("completeness"),
 "Session or Conversation ID":session.get("session_id") or session.get("conversation_id"),
 "Session Resume Command":session.get("resume_command"),
 "Artifact Stem":metadata.get("artifact_stem") or stem
}
# The two totals are distinct rows and are never reconciled into one. The
# source-and-scope row states both scopes as recorded (Host Guide 7.3).
scope_expected="legacy="+str(tele.get("legacy_total_scope"))+" verified="+str(tele.get("verified_total_scope"))
if identity_map.get("Token Source and Scope") not in {scope_expected,"Unknown","Not available"}:
 raise SystemExit("identity mirror mismatch: Token Source and Scope")
for field,expected in checks.items():
 observed=identity_map.get(field)
 allowed={value(expected)}
 if expected is None: allowed.update({"Unknown","Not available"})
 if observed not in allowed: raise SystemExit(f"identity mirror mismatch: {field}")
snapshot_checks={
 "Pass ID":metadata.get("pass_id") or pass_id,"Artifact Stem":metadata.get("artifact_stem") or stem,"Agent Started":metadata.get("agent_started"),"Capture Process Exit Status":metadata.get("capture_process_exit_status"),"Code Agent Exit Status":metadata.get("code_agent_exit_status"),"Collector Exit Status":metadata.get("collector_exit_status"),"Agent Exit Code":metadata.get("agent_exit_code"),"Duration Seconds":metadata.get("duration_seconds"),"Total Tokens Used":metadata.get("total_tokens_used"),"Verified Total Tokens":tele.get("total_tokens"),"Legacy Total Scope":tele.get("legacy_total_scope"),"Verified Total Scope":tele.get("verified_total_scope"),"Token Completeness":tele.get("completeness"),"Metadata Format Version":metadata.get("metadata_format_version"),"Input Tokens":tele.get("input_tokens"),"Cached Input Tokens":tele.get("cached_input_tokens"),"Output Tokens":tele.get("output_tokens"),"Reasoning Tokens":tele.get("reasoning_tokens"),"Session or Conversation ID":session.get("session_id") or session.get("conversation_id"),"Resume Command":session.get("resume_command"),"Product Result":product_map.get(metadata.get("product_result"),metadata.get("product_result")),"Workflow Finalization Result":workflow_map.get(metadata.get("workflow_finalization_result"),metadata.get("workflow_finalization_result")),"Metadata Finalized":metadata.get("metadata_finalized"),"Continuation State Finalized":metadata.get("continuation_state_finalized")}
for field,expected in snapshot_checks.items():
 observed=snapshot_map.get(field); allowed={value(expected)}
 if expected is None: allowed.update({"Unknown","Not available"})
 if observed not in allowed: raise SystemExit(f"Pass Execution Snapshot mirror mismatch: {field}")
if "### Pass-produced changes" not in report or "### Inherited changes remaining" not in report: raise SystemExit("Files Modified separation is incomplete")
for suffix,path in (("-prompt.txt","prompts"),("-launcher.zsh","launchers"),("-metadata.json","metadata-reports"),("-report.md","reports"),("-raw.log","logs/raw-logs"),("-clean.log","logs/clean-logs"),("-meta.log","logs/meta-logs"),("-continuation-state.json","metadata-reports")):
 expected=f"build-report-logs/{path}/{stem}{suffix}"
 if expected not in report: raise SystemExit("missing standard artifact reference: "+expected)' \
  "$AI_REPORT_PATH" "$AI_REPORT_TEMPLATE" "$metadata_tmp" "$AI_PASS_ID" "$AI_ARTIFACT_STEM" 2>"$diagnostics" \
  || {
    rm -f -- "$metadata_tmp" "$continuation_tmp" 2>/dev/null || true
    die 60 report "Host report validation or metadata mirror agreement failed: $AI_REPORT_PATH; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"
  }

local transaction_diagnostics="$AI_TMP_ROOT/runtime/finalization-transaction-errors.log"
local provisional_backup="$AI_TMP_ROOT/runtime/provisional-metadata-before-finalization.json"
local runtime_backup="$AI_TMP_ROOT/runtime/runtime-state-before-finalization.json"

# ---------------------------------------------------------------------------
# Preserve the detailed records, build the hashed evidence index, and project
# the compact finalized record (Host Guide 8.13 finalization order, 8.14).
#
# Preservation happens here, before anything that can fail, so compaction can
# never run ahead of the detail it replaces.
# ---------------------------------------------------------------------------
local evidence_index="${AI_METADATA_EVIDENCE_INDEX_PATH:-$AI_TMP_ROOT/runtime/metadata-evidence-index.json}"
local compact_tmp="${AI_METADATA_PATH:h}/.${AI_METADATA_PATH:t}.compact.$$"
local compact_diagnostics="$AI_TMP_ROOT/runtime/compact-finalization-errors.log"
inside "$evidence_index" "$AI_TMP_ROOT"

local compaction_summary
compaction_summary="$(python3 - "$metadata_tmp" "$AI_RUNTIME_STATE_PATH" "$provisional_backup" "$runtime_backup" \
  "$evidence_index" "$compact_tmp" "$AI_PROJECT_ROOT" "$AI_REPORT_ROOT" "$AI_ARTIFACT_STEM" \
  "$AI_PASS_ID" "$AI_METADATA_SCHEMA" "$telemetry_result" "$AI_REPORT_PATH" "$continuation_tmp" \
  "$AI_PROMPT_PATH" "$AI_LAUNCHER_PATH" "$AI_RAW_LOG_PATH" "$AI_CLEAN_LOG_PATH" "$AI_META_LOG_PATH" \
  "$pub_start" "$priv_start" "$pub" "$priv" "$inherited_manifest" "$pass_manifest" "$workflow_manifest" \
  <<'PY' 2>"$compact_diagnostics"
import hashlib, json, os, sys, tempfile

(metadata_candidate, runtime_path, provisional_backup, runtime_backup,
 index_path, compact_path, project_root, report_root, stem, pass_id,
 schema_path, telemetry_path, report_path, continuation_candidate,
 prompt_path, launcher_path, raw_log, clean_log, meta_log,
 pub_start, priv_start, pub_end, priv_end,
 inherited_manifest, pass_manifest, workflow_manifest) = sys.argv[1:27]

try:
    import jsonschema
except Exception:
    raise SystemExit("jsonschema package unavailable")


def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def atomic_bytes(path, payload):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".tmp-", dir=directory)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def relative(path):
    return os.path.relpath(os.path.realpath(path), project_root)


# Step 2 of the finalization order: preserve the detailed records first.
with open(metadata_candidate, "rb") as handle:
    atomic_bytes(provisional_backup, handle.read())
with open(runtime_path, "rb") as handle:
    atomic_bytes(runtime_backup, handle.read())

data = load(metadata_candidate)
runtime = load(runtime_path)

# ---- evidence index -------------------------------------------------------
# Movable roles carry their exact active and archive candidates so ordinary
# rotation never invalidates a correct index (Host Guide 8.14, 12.5).
archive_pairs = {
    "report": (os.path.join(report_root, "reports", stem + "-report.md"),
               os.path.join(report_root, "reports", "reports-archive", stem + "-report.md")),
    "launcher": (os.path.join(report_root, "launchers", stem + "-launcher.zsh"),
                 os.path.join(report_root, "launchers", "launchers-archive", stem + "-launcher.zsh")),
}
stable_roles = [
    ("provisional_metadata_backup", provisional_backup),
    ("runtime_state_backup", runtime_backup),
    ("provider_telemetry", telemetry_path),
    ("continuation_state", continuation_candidate),
    ("prompt", prompt_path),
    ("raw_log", raw_log),
    ("clean_log", clean_log),
    ("meta_log", meta_log),
    ("public_start_snapshot", pub_start),
    ("private_start_snapshot", priv_start),
    ("public_end_snapshot", pub_end),
    ("private_end_snapshot", priv_end),
    ("inherited_change_manifest", inherited_manifest),
    ("pass_produced_change_manifest", pass_manifest),
    ("workflow_change_manifest", workflow_manifest),
]
conditional_roles = [
    ("runtime_seed_manifest", os.path.join(os.path.dirname(index_path), "runtime-seed-manifest.json")),
    ("capture_status_contract", os.path.join(os.path.dirname(index_path), "capture-status-contract.json")),
    ("provider_telemetry_fixture_results", os.path.join(os.path.dirname(index_path), "provider-telemetry-fixture-results.json")),
    ("metadata_contract_fixture_results", os.path.join(os.path.dirname(index_path), "metadata-contract-fixture-results.json")),
]

entries = []


def add_entry(role, path, candidates=None):
    if not os.path.isfile(path):
        raise SystemExit("required evidence is absent for role " + role + ": " + relative(path))
    with open(path, "rb") as handle:
        payload = handle.read()
    resolved = relative(path)
    if resolved.startswith("..") or os.path.isabs(resolved):
        raise SystemExit("evidence path escapes the project root: " + resolved)
    entries.append({
        "role": role,
        "path_candidates": candidates or [resolved],
        "path": resolved,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "byte_length": len(payload),
    })


for role, (active, archived) in archive_pairs.items():
    present = [p for p in (active, archived) if os.path.isfile(p)]
    if len(present) != 1:
        raise SystemExit("role " + role + " must resolve through exactly one candidate; found "
                         + str(len(present)))
    add_entry(role, present[0], [relative(active), relative(archived)])
for role, path in stable_roles:
    add_entry(role, path)
for role, path in conditional_roles:
    if os.path.isfile(path):
        add_entry(role, path)

index = {
    "workflow_version": "v2.4.1",
    "index_version": "metadata-evidence-index-v1",
    "pass_id": pass_id,
    "artifact_stem": stem,
    "created_at": data.get("post_pass_completed_at"),
    "entries": sorted(entries, key=lambda item: item["role"]),
}

schema = load(schema_path)
resolver = jsonschema.RefResolver(base_uri="", referrer=schema)


def validate_against(branch, instance):
    target = dict(schema["definitions"][branch])
    target["definitions"] = schema["definitions"]
    jsonschema.Draft7Validator(target, resolver=resolver).validate(instance)


validate_against("metadata_evidence_index", index)

# The exact bytes that will be installed are the bytes that are hashed.
index_bytes = (json.dumps(index, indent=2, sort_keys=True) + "\n").encode("utf-8")
index_digest = hashlib.sha256(index_bytes).hexdigest()

# ---- compact projection ---------------------------------------------------
telemetry = data["telemetry"]
session = data["session"]
build = data.get("build_result") or {}
recommended = data.get("recommended_next_prompt") or {}
next_action = recommended.get("action")

compact = {
    "workflow_version": "v2.4.1",
    "metadata_format_version": "compact-final-v1",
    "metadata_finalized": True,
    "project_name": data["project_name"],
    "project_root": data["project_root"],
    "pass_id": data["pass_id"],
    "pass_name": data["pass_name"],
    "artifact_stem": data["artifact_stem"],
    "pass_type": data["pass_type"],
    "date": data["date"],
    "status": data["status"],
    "objective": data["objective"],
    "code_agent": data["code_agent"],
    "model": data["model"],
    "effort": data["effort"],
    "duration_seconds": data["duration_seconds"],
    "total_tokens_used": data["total_tokens_used"],
    "telemetry": telemetry,
    "session": session,
    "lifecycle": {
        "agent_started_at": data["agent_started_at"],
        "agent_exited_at": data["agent_exited_at"],
        "finalized_at": data["finalized_at"],
        "capture_process_exit_status": data["capture_process_exit_status"],
        "code_agent_exit_status": data["code_agent_exit_status"],
        "code_agent_exit_status_source": data["code_agent_exit_status_source"],
        "termination_detail": data["termination_detail"],
        "collector_exit_status": data["collector_exit_status"],
        "collector_status": data["collector_status"],
        "workflow_finalization_result": "succeeded",
    },
    "result": {
        "product_result": data["product_result"],
        "build_outcome": build.get("outcome", "unknown"),
        "unresolved_issue_count": len(data.get("unresolved_issues") or []),
        "recommended_next_pass": next_action if next_action else None,
    },
    # Counts are derived from the authoritative lists and manifests, never
    # transcribed, so they cannot drift from the records they summarize.
    "changes": {
        "files_read_count": len(data.get("files_read") or []),
        "files_created_count": len(data.get("files_created") or []),
        "files_modified_count": len(data.get("files_modified") or []),
        "inherited_change_count": len(load(inherited_manifest).get("changes") or []),
        "pass_produced_change_count": len(load(pass_manifest).get("changes") or []),
        "workflow_file_change_count": len(load(workflow_manifest).get("changes") or []),
        "write_scope_valid": (data.get("write_scope") or {}).get("write_scope_valid") is True,
    },
    "checks": {
        "report_valid": True,
        "metadata_schema_valid": True,
        "continuation_state_finalized": True,
        "report_metadata_agreement": True,
        "agents_md_authorized": data.get("agents_md_authorized") is True,
        "archive_eligible": True,
    },
    "evidence": {
        "index_path": relative(index_path),
        "index_sha256": index_digest,
    },
}

if compact["duration_seconds"] is None:
    raise SystemExit("duration_seconds is unavailable; a finalized record requires both accepted runner boundaries")

validate_against("finalized_metadata_compact_v1", compact)

compact_bytes = (json.dumps(compact, indent=2, sort_keys=True) + "\n").encode("utf-8")
atomic_bytes(index_path, index_bytes)
atomic_bytes(compact_path, compact_bytes)

# Size guidance is reported, never enforced by truncation (Host Guide 8.13).
line_count = compact_bytes.count(b"\n")
print("\t".join([
    index_digest,
    str(line_count),
    str(len(compact_bytes)),
    "within" if (100 <= line_count <= 160 and 4096 <= len(compact_bytes) <= 8192) else "outside",
]))
PY
)" \
  || {
    rm -f -- "$metadata_tmp" "$continuation_tmp" "$compact_tmp" 2>/dev/null || true
    die 60 finalization "compact finalization or evidence index failed; diagnostics retained at ${compact_diagnostics#$AI_PROJECT_ROOT/}"
  }

local evidence_index_sha256 compact_lines compact_bytes compact_within_guidance
IFS=$'\t' read -r evidence_index_sha256 compact_lines compact_bytes compact_within_guidance \
  <<< "$compaction_summary"
[[ -n "$evidence_index_sha256" ]] \
  || die 60 finalization "compact finalization did not report an evidence-index digest"

python3 -c 'import hashlib,json,os,re,shutil,sys,tempfile,datetime

(
 report_root,
 current_stem,
 metadata_path,
 metadata_candidate,
 continuation_path,
 continuation_candidate,
 runtime_path,
 done_path,
 meta_path,
 provisional_backup,
 runtime_backup,
 tmp_root,
 product_result,
 evidence_index_path,
 evidence_index_sha256
)=sys.argv[1:16]

def load_json(path):
 with open(path,encoding="utf-8") as f:
  return json.load(f)

def atomic_bytes(path,data):
 directory=os.path.dirname(path) or "."
 os.makedirs(directory,exist_ok=True)
 fd,tmp=tempfile.mkstemp(prefix="."+os.path.basename(path)+".tmp-",dir=directory)
 try:
  with os.fdopen(fd,"wb") as f:
   f.write(data)
   f.flush()
   os.fsync(f.fileno())
  os.replace(tmp,path)
 except Exception:
  try: os.unlink(tmp)
  except FileNotFoundError: pass
  raise

def atomic_json(path,data):
 atomic_bytes(
  path,
  (json.dumps(data,indent=2,sort_keys=True)+"\n").encode("utf-8")
 )

def copy_retained(source,destination):
 with open(source,"rb") as f:
  atomic_bytes(destination,f.read())

def artifact_key(stem):
 match=re.fullmatch(r"([0-9]{2})-([0-9]{2})-([0-9]{2})_P([0-9]+)(?:\.([0-9]+))?_(.+)",stem)
 if match is None:
  return None
 return (
  int(match.group(4)),
  int(match.group(5) or 0),
  int(match.group(1)),
  int(match.group(2)),
  int(match.group(3)),
  match.group(6)
 )

# The provisional and runtime records were already preserved before compaction
# (Host Guide 8.13 step 2); the backups are re-verified here rather than
# re-taken, because metadata_path now holds the pre-finalization record and
# metadata_candidate holds the compact projection.
for _backup in (provisional_backup, runtime_backup):
 if not os.path.isfile(_backup):
  raise RuntimeError("preserved evidence is missing before finalization: "+_backup)

archive_moves=[]
continuation_installed=False
metadata_installed=False
signal_installed=False
meta_success_appended=False

failed_metadata=os.path.join(
 tmp_root,
 "runtime",
 "failed-finalized-metadata.json"
)
failed_continuation=os.path.join(
 tmp_root,
 "runtime",
 "failed-continuation-state.json"
)

try:
 classes={
  "launcher":(
   os.path.join(report_root,"launchers"),
   "-launcher.zsh",
   "launchers-archive"
  ),
  "report":(
   os.path.join(report_root,"reports"),
   "-report.md",
   "reports-archive"
  ),
  "metadata":(
   os.path.join(report_root,"metadata-reports"),
   "-metadata.json",
   "metadata-reports-archive"
  )
 }

 sets={}
 for kind,(directory,suffix,archive) in classes.items():
  if not os.path.isdir(directory):
   continue

  for name in os.listdir(directory):
   if name.endswith(suffix):
    stem=name[:-len(suffix)]
    sets.setdefault(stem,{})[kind]=os.path.join(directory,name)

 eligible=[]

 for stem,paths in sets.items():
  if stem==current_stem:
   continue

  if set(paths)!=set(classes):
   continue

  try:
   metadata=load_json(paths["metadata"])
  except Exception:
   continue

  if metadata.get("artifact_stem")!=stem:
   continue

  if metadata.get("workflow_finalization_result")!="succeeded":
   continue

  if metadata.get("metadata_finalized") is not True:
   continue

  if metadata.get("continuation_state_finalized") is not True:
   continue

  if metadata.get("metadata_schema_valid") is not True:
   continue

  if metadata.get("report_valid") is not True:
   continue

  if metadata.get("archive_eligible") is not True:
   continue

  key=artifact_key(stem)
  if key is None:
   continue
  eligible.append((key,stem,paths))

 # The current candidate becomes the fifty-first completed active set only
 # after this transaction commits. It is deliberately left active.
 if len(eligible)+1>=51:
  selected=sorted(eligible)[:50]
  planned=[]

  for _,stem,paths in selected:
   for kind in ("launcher","report","metadata"):
    directory,suffix,archive=classes[kind]
    destination=os.path.join(
     directory,
     archive,
     os.path.basename(paths[kind])
    )

    if os.path.exists(destination):
     raise RuntimeError("archive collision: "+destination)

    planned.append((paths[kind],destination))

  for source,destination in planned:
   os.makedirs(os.path.dirname(destination),exist_ok=True)
   os.replace(source,destination)
   archive_moves.append((source,destination))

 runtime=load_json(runtime_path)
 runtime.update({
  "workflow_finalization_result":"succeeded",
  "post_pass_completed":True,
  "post_pass_completed_at":
   datetime.datetime.now(
    datetime.timezone.utc
   ).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "continuation_state_finalized":True,
  "metadata_finalized":True
 })
 atomic_json(runtime_path,runtime)

 line=(
  "["+
  datetime.datetime.now(
   datetime.timezone.utc
  ).strftime("%Y-%m-%dT%H:%M:%SZ")+
  "] post-pass complete\n"
  "product_result="+product_result+"\n"
  "workflow_finalization_result=succeeded\n"
  "continuation_state="+
  os.path.relpath(
   continuation_path,
   os.path.dirname(report_root)
  )+"\n"
  "metadata="+
  os.path.relpath(
   metadata_path,
   os.path.dirname(report_root)
  )+"\n"
 )

 with open(meta_path,"a",encoding="utf-8") as f:
  written=f.write(line)

  if written!=len(line):
   raise RuntimeError(
    "short append while writing final meta evidence"
   )

  f.flush()
  os.fsync(f.fileno())

 meta_success_appended=True

 os.replace(continuation_candidate,continuation_path)
 continuation_installed=True

 # The finalized metadata replacement is the authoritative finalization
 # commit point. Any later supporting-evidence failure rolls it back.
 os.replace(metadata_candidate,metadata_path)
 metadata_installed=True

 # Re-verify the installed evidence index against the digest recorded inside
 # the compact record before publishing completion. Installing bytes that
 # differ from the hashed candidate must prevent the completion marker
 # (Host Guide 8.14).
 with open(evidence_index_path,"rb") as f:
  installed_index=f.read()
 if hashlib.sha256(installed_index).hexdigest()!=evidence_index_sha256:
  raise RuntimeError("installed evidence index does not match the hash recorded in compact metadata")
 with open(metadata_path,encoding="utf-8") as f:
  installed_metadata=json.load(f)
 if installed_metadata.get("evidence",{}).get("index_sha256")!=evidence_index_sha256:
  raise RuntimeError("installed compact metadata does not carry the verified evidence-index hash")
 if installed_metadata.get("metadata_format_version")!="compact-final-v1":
  raise RuntimeError("installed metadata is not compact-final-v1")

 # Publish completion only after finalized continuation state and metadata
 # are durably installed and their hashes re-verified.
 atomic_bytes(done_path,b"success\n")
 signal_installed=True

except Exception:
 if signal_installed:
  try:
   os.unlink(done_path)
  except FileNotFoundError:
   pass

 try:
  copy_retained(runtime_backup,runtime_path)
 except Exception:
  pass

 for source,destination in reversed(archive_moves):
  try:
   if os.path.exists(destination):
    os.makedirs(os.path.dirname(source),exist_ok=True)
    os.replace(destination,source)
  except Exception:
   pass

 if metadata_installed:
  try:
   if os.path.exists(metadata_path):
    os.replace(metadata_path,failed_metadata)
  except Exception:
   pass

 try:
  copy_retained(provisional_backup,metadata_path)
 except Exception:
  pass

 if continuation_installed:
  try:
   if os.path.exists(continuation_path):
    os.replace(continuation_path,failed_continuation)
  except Exception:
   pass

 if meta_success_appended:
  try:
   rollback_line=(
    "["+
    datetime.datetime.now(
     datetime.timezone.utc
    ).strftime("%Y-%m-%dT%H:%M:%SZ")+
    "] finalization rollback\n"
    "workflow_finalization_result=failed\n"
   )

   with open(meta_path,"a",encoding="utf-8") as f:
    f.write(rollback_line)
    f.flush()
    os.fsync(f.fileno())
  except Exception:
   pass

 raise' \
  "$AI_REPORT_ROOT" \
  "$AI_ARTIFACT_STEM" \
  "$AI_METADATA_PATH" \
  "$compact_tmp" \
  "$AI_CONTINUATION_STATE_PATH" \
  "$continuation_tmp" \
  "$AI_RUNTIME_STATE_PATH" \
  "$AI_POST_PASS_DONE_PATH" \
  "$AI_META_LOG_PATH" \
  "$provisional_backup" \
  "$runtime_backup" \
  "$AI_TMP_ROOT" \
  "$product" \
  "$evidence_index" \
  "$evidence_index_sha256" \
  2>"$transaction_diagnostics" \
  || {
    rm -f -- "$metadata_tmp" "$compact_tmp" 2>/dev/null || true
    die 60 finalization "finalization transaction failed and rollback was attempted; diagnostics retained at ${transaction_diagnostics#$AI_PROJECT_ROOT/}"
  }

rm -f -- "$metadata_tmp" 2>/dev/null || true

print -- "Workflow finalization succeeded: product_result=$product metadata_format_version=compact-final-v1"
print -- "Compact metadata: ${AI_METADATA_PATH#$AI_PROJECT_ROOT/} (${compact_lines} lines, ${compact_bytes} bytes; size guidance ${compact_within_guidance})"
print -- "Evidence index: ${evidence_index#$AI_PROJECT_ROOT/} sha256=${evidence_index_sha256}"
exit 0
