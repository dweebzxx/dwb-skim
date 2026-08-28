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
  local diagnostics="${target:h}/cli-pre-pass-python-errors.log"
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
for n in AI_PROMPT_PATH AI_LAUNCHER_PATH AI_METADATA_PATH AI_CONTINUATION_STATE_PATH AI_TMP_ROOT AI_COLLECTOR_CONTROL_PATH AI_COLLECTOR_PID_PATH AI_COLLECTOR_STATE_PATH AI_RUNNER_CONTROL_PATH AI_POST_PASS_DONE_PATH AI_RAW_LOG_PATH AI_CLEAN_LOG_PATH; do need "$n"; done
inside "$AI_TMP_ROOT" "$AI_REPORT_ROOT"
inside "$AI_COLLECTOR_CONTROL_PATH" "$AI_TMP_ROOT"
inside "$AI_COLLECTOR_STATE_PATH" "$AI_TMP_ROOT"
inside "$AI_RUNNER_CONTROL_PATH" "$AI_TMP_ROOT"

local failed_root="$AI_REPORT_ROOT/logs/failed-attempts/$AI_ARTIFACT_STEM"
local pre_pass_operation="${AI_PRE_PASS_OPERATION:-run}"

if [[ "$pre_pass_operation" == preserve-failed-attempt ]]; then
  need_file "$AI_RUNTIME_STATE_PATH" "failed-attempt runtime state"

  local preservation_diagnostics="${AI_RUNTIME_STATE_PATH:h}/cli-pre-pass-preservation-python-errors.log"
  local prior_agent_started

  prior_agent_started="$(python3 -c 'import json,sys
data=json.load(open(sys.argv[1],encoding="utf-8"))
print(str(data.get("agent_started")).lower())' \
    "$AI_RUNTIME_STATE_PATH" 2>>"$preservation_diagnostics")" \
    || die 30 collision "cannot read failed-attempt lifecycle state; diagnostics retained at ${preservation_diagnostics#$AI_PROJECT_ROOT/}"

  [[ "$prior_agent_started" == false ]] \
    || die 30 collision "same-ID preservation is prohibited because agent_started is not false"

  local attempt_number=1
  local attempt_dir

  while :; do
    attempt_dir="$failed_root/attempt-${(l:3::0:)attempt_number}"
    [[ ! -e "$attempt_dir" ]] && break
    (( attempt_number++ ))
  done

  mkdir -p -- "$attempt_dir" \
    || die 90 collision "cannot create failed-attempt directory: $attempt_dir"

  preserve_failed_path() {
    local source="$1"
    local destination_name="$2"

    [[ -e "$source" || -L "$source" ]] || return 0

    mv -- "$source" "$attempt_dir/$destination_name" \
      || die 90 collision "cannot preserve failed-attempt evidence: $source"
  }

  preserve_failed_path "$AI_PROMPT_PATH" "${AI_PROMPT_PATH:t}"
  preserve_failed_path "$AI_LAUNCHER_PATH" "${AI_LAUNCHER_PATH:t}"
  preserve_failed_path "$AI_METADATA_PATH" "${AI_METADATA_PATH:t}"
  preserve_failed_path "$AI_CONTINUATION_STATE_PATH" "${AI_CONTINUATION_STATE_PATH:t}"
  preserve_failed_path "${AI_RAW_LOG_PATH:-}" "${AI_RAW_LOG_PATH:t}"
  preserve_failed_path "${AI_CLEAN_LOG_PATH:-}" "${AI_CLEAN_LOG_PATH:t}"
  preserve_failed_path "$AI_META_LOG_PATH" "${AI_META_LOG_PATH:t}"
  preserve_failed_path "$AI_TMP_ROOT" "tmp-runtime-evidence"

  {
    print -- "artifact_stem=$AI_ARTIFACT_STEM"
    print -- "attempt_directory=${attempt_dir#$AI_PROJECT_ROOT/}"
    print -- "agent_started=false"
    print -- "preserved_at=$(now)"
    print -- "replacement_status=active-paths-cleared"
  } > "$attempt_dir/failure-summary.txt" \
    || die 90 collision "cannot write failed-attempt summary: $attempt_dir/failure-summary.txt"

  print -r -- "preservation_complete" > "$attempt_dir/preservation-complete" \
    || die 90 collision "cannot write failed-attempt preservation marker"

  print -- "Failed attempt preserved: ${attempt_dir#$AI_PROJECT_ROOT/}"
  exit 0
fi

[[ "$pre_pass_operation" == run ]] \
  || die 2 input "unsupported AI_PRE_PASS_OPERATION: $pre_pass_operation"

need_file "$AI_PROMPT_PATH" "saved prompt"
need_file "$AI_LAUNCHER_PATH" "saved launcher"

local diagnostics="$AI_TMP_ROOT/runtime/cli-pre-pass-python-errors.log"
mkdir -p -- "$AI_TMP_ROOT/runtime" "$AI_COLLECTOR_CONTROL_PATH" "$AI_RUNNER_CONTROL_PATH" \
  || die 90 runtime "cannot create runtime paths"

local init
init="$(python3 -c 'import json,sys
data=json.load(open(sys.argv[1],encoding="utf-8"))
print("true" if data.get("initialization_ready") is True else "false")' \
  "$AI_RUNTIME_STATE_PATH" 2>>"$diagnostics")" \
  || die 30 continuation "cannot read initialization readiness; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"

[[ "$init" == true ]] \
  || die 30 continuation "initialization readiness is not established"

if [[ "${AI_SAME_ID_RETRY:-0}" == 1 ]]; then
  need AI_FAILED_ATTEMPT_DIR
  inside "$AI_FAILED_ATTEMPT_DIR" "$failed_root"

  [[ -f "$AI_FAILED_ATTEMPT_DIR/preservation-complete" ]] \
    || die 30 collision "same-ID retry requires a completed failed-attempt preservation marker: $AI_FAILED_ATTEMPT_DIR/preservation-complete"
fi

local -a active_collisions
local active_path

for active_path in \
  "$AI_METADATA_PATH" \
  "$AI_CONTINUATION_STATE_PATH" \
  "${AI_RAW_LOG_PATH:-}" \
  "${AI_CLEAN_LOG_PATH:-}" \
  "$AI_POST_PASS_DONE_PATH"
do
  [[ -z "$active_path" || ! -e "$active_path" ]] \
    || active_collisions+=("$active_path")
done

(( ${#active_collisions} == 0 )) \
  || die 20 collision "active pass artifacts already exist after preservation: ${(j:, :)active_collisions}"

local pub="$AI_TMP_ROOT/runtime/public-start.json"
local priv="$AI_TMP_ROOT/runtime/private-start.json"
local protected_start="$AI_TMP_ROOT/runtime/protected-workflow-start.json"

# The skill gate (skill_gate_reconcile, below) creates these two directories
# via mkdir -p if absent. That must happen before this snapshot, not after,
# or the gate's own bootstrap of an empty catalog/store reads as an
# unauthorized pass-produced change at cli-post-pass.zsh's write-scope check.
mkdir -p -- \
  "${AI_SKILL_STORE_PATH:-$AI_PROJECT_ROOT/.private/.agents/skills-store}" \
  "${AI_SKILL_CATALOG_PATH:-$AI_PROJECT_ROOT/.private/.agents/skills}" \
  || die 90 skills "cannot pre-create skill gate paths before snapshot"

# ---------------------------------------------------------------------------
# Runtime evidence paths and the narrowly authorized bootstrap/adoption seed
# mode (Host Guide 9.7, 15.2, 16.7).
# ---------------------------------------------------------------------------
local normalized_telemetry_abs="$AI_TMP_ROOT/runtime/provider-telemetry.json"
local evidence_index_abs="$AI_TMP_ROOT/runtime/metadata-evidence-index.json"
local seed_manifest_abs="$AI_TMP_ROOT/runtime/runtime-seed-manifest.json"
local normalized_telemetry_rel="${normalized_telemetry_abs#$AI_PROJECT_ROOT/}"
local seed_manifest_rel=""
local seed_mode=false
local pre_seed_snapshot=""
local seed_attribution="$AI_TMP_ROOT/runtime/runtime-seed-attribution.json"

if [[ -n "${AI_NORMALIZED_TELEMETRY_PATH:-}" ]]; then
  [[ "$AI_NORMALIZED_TELEMETRY_PATH" == "$normalized_telemetry_abs" ]] \
    || die 20 path "AI_NORMALIZED_TELEMETRY_PATH must be $normalized_telemetry_abs"
  inside "$AI_NORMALIZED_TELEMETRY_PATH" "$AI_TMP_ROOT"
fi
if [[ -n "${AI_METADATA_EVIDENCE_INDEX_PATH:-}" ]]; then
  [[ "$AI_METADATA_EVIDENCE_INDEX_PATH" == "$evidence_index_abs" ]] \
    || die 20 path "AI_METADATA_EVIDENCE_INDEX_PATH must be $evidence_index_abs"
  inside "$AI_METADATA_EVIDENCE_INDEX_PATH" "$AI_TMP_ROOT"
fi

if [[ -n "${AI_RUNTIME_SEED_MANIFEST_PATH:-}" ]]; then
  # Seed evidence is accepted only for an authorized bootstrap or adoption
  # pass. An ordinary pass that presents it is a launcher defect, not a
  # relaxation opportunity.
  [[ "$AI_PASS_TYPE" == bootstrap || "$AI_PASS_TYPE" == adoption ]] \
    || die 20 seed "runtime seed evidence is not permitted for pass type $AI_PASS_TYPE"
  [[ "$AI_RUNTIME_SEED_MANIFEST_PATH" == "$seed_manifest_abs" ]] \
    || die 20 seed "AI_RUNTIME_SEED_MANIFEST_PATH must be $seed_manifest_abs"
  inside "$AI_RUNTIME_SEED_MANIFEST_PATH" "$AI_TMP_ROOT"
  need_file "$AI_RUNTIME_SEED_MANIFEST_PATH" "runtime seed manifest"

  local seed_diagnostics="$AI_TMP_ROOT/runtime/cli-pre-pass-seed-errors.log"
  pre_seed_snapshot="$(python3 - "$AI_RUNTIME_SEED_MANIFEST_PATH" "$AI_PASS_ID" "$AI_ARTIFACT_STEM" "$AI_PROJECT_ROOT" "$seed_attribution" <<'PY' 2>>"$seed_diagnostics"
import hashlib, json, os, sys
manifest_path, pass_id, stem, project_root, attribution_path = sys.argv[1:6]
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)
if not isinstance(manifest, dict):
    raise SystemExit("seed manifest root must be an object")
required = {"workflow_version", "pass_id", "artifact_stem",
            "pre_seed_snapshot_path", "transaction_result", "entries"}
missing = sorted(required - set(manifest))
if missing:
    raise SystemExit("missing seed-manifest fields: " + ", ".join(missing))
if manifest["workflow_version"] != "v2.4.1":
    raise SystemExit("seed manifest workflow_version mismatch")
if manifest["pass_id"] != pass_id or manifest["artifact_stem"] != stem:
    raise SystemExit("seed manifest identity does not match this pass")
if manifest["transaction_result"] != "succeeded":
    raise SystemExit("seed transaction did not succeed: "
                     + str(manifest["transaction_result"]))
entries = manifest["entries"]
if not isinstance(entries, list) or not entries:
    raise SystemExit("seed manifest must record at least one destination")
seen = set()
for entry in entries:
    if not isinstance(entry, dict):
        raise SystemExit("seed manifest entry must be an object")
    for field in ("source_path", "destination_path", "sha256", "disposition"):
        if field not in entry:
            raise SystemExit("seed manifest entry missing " + field)
    destination = entry["destination_path"]
    if os.path.isabs(destination) or ".." in destination.split("/"):
        raise SystemExit("seed destination must be project-relative and "
                         "must not escape the project root: " + destination)
    if destination in seen:
        raise SystemExit("duplicate seed destination: " + destination)
    seen.add(destination)
    if entry["disposition"] not in ("created", "reused-identical"):
        raise SystemExit("invalid seed disposition for " + destination
                         + ": " + str(entry["disposition"]))
    digest = entry["sha256"]
    if not isinstance(digest, str) or len(digest) != 64:
        raise SystemExit("seed entry sha256 must be 64 hex characters: "
                         + destination)
    absolute = os.path.join(project_root, destination)
    if not os.path.isfile(absolute):
        raise SystemExit("seeded destination is absent: " + destination)
    with open(absolute, "rb") as handle:
        actual = hashlib.sha256(handle.read()).hexdigest()
    if actual != digest:
        raise SystemExit("seeded file does not match its recorded digest: "
                         + destination)
snapshot = manifest["pre_seed_snapshot_path"]
if os.path.isabs(snapshot) or ".." in snapshot.split("/"):
    raise SystemExit("pre-seed snapshot path must be project-relative")
if not os.path.isfile(os.path.join(project_root, snapshot)):
    raise SystemExit("pre-seed snapshot is absent: " + snapshot)
# Disposition drives change attribution: a destination this seed transaction
# created belongs to the active control pass, and one it safely reused does
# not (Host Guide 15.2, 16.7). Post-pass consumes this record; it must not
# infer attribution from timestamps or from the start snapshot alone, because
# the seed ran before that snapshot was taken.
attribution = {
    "created": sorted(entry["destination_path"] for entry in entries
                      if entry["disposition"] == "created"),
    "reused_identical": sorted(entry["destination_path"] for entry in entries
                               if entry["disposition"] == "reused-identical"),
    "pre_seed_snapshot_path": snapshot,
}
with open(attribution_path, "w", encoding="utf-8") as handle:
    json.dump(attribution, handle, indent=2, sort_keys=True)
    handle.write("\n")
print(snapshot)
PY
)" \
    || die 30 seed "runtime seed manifest is invalid; diagnostics retained at ${seed_diagnostics#$AI_PROJECT_ROOT/}"
  seed_manifest_rel="${AI_RUNTIME_SEED_MANIFEST_PATH#$AI_PROJECT_ROOT/}"
  seed_mode=true
  print -- "[$(now)] runtime seed manifest validated; pre_seed_snapshot=$pre_seed_snapshot attribution=${seed_attribution#$AI_PROJECT_ROOT/}" >> "$AI_META_LOG_PATH" \
    || die 90 meta "cannot append seed validation evidence"
fi

python3 -c 'import hashlib,json,os,subprocess,sys,tempfile

def signature(repo,path):
 full=os.path.join(repo,path)
 try:
  os.lstat(full)
 except FileNotFoundError:
  cp=subprocess.run(["git","-C",repo,"rev-parse",f"HEAD:{path}"],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
  return "git-object:"+cp.stdout.strip() if cp.returncode==0 and cp.stdout.strip() else None
 if os.path.islink(full):
  return "symlink-sha256:"+hashlib.sha256(os.readlink(full).encode("utf-8","surrogateescape")).hexdigest()
 if os.path.isfile(full):
  h=hashlib.sha256()
  with open(full,"rb") as f:
   for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
  return "sha256:"+h.hexdigest()
 return None

def snap(repo,label):
 if not os.path.isdir(os.path.join(repo,".git")):
  return {"repository":label,"present":False,"head":None,"branch":None,"entries":[]}
 cp=subprocess.run(["git","-C",repo,"status","--porcelain=v1","-z","--untracked-files=all"],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 if cp.returncode: raise RuntimeError(cp.stderr.decode(errors="replace"))
 records=cp.stdout.split(b"\0"); out=[]; i=0
 while i < len(records):
  rec=records[i]; i+=1
  if not rec: continue
  text=rec.decode("utf-8","surrogateescape")
  status=text[:2]; path=text[3:]; original=None
  if "R" in status or "C" in status:
   if i < len(records) and records[i]:
    original=records[i].decode("utf-8","surrogateescape"); i+=1
  if path==".DS_Store" or path.endswith("/.DS_Store"): continue
  out.append({"repository":label,"status":status,"status_type":status,"path":path,"original_path":original,"signature":signature(repo,path),"content_signature":signature(repo,path),"classification":"inherited","ignored_noise":False})
 head=subprocess.run(["git","-C",repo,"rev-parse","HEAD"],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 branch=subprocess.run(["git","-C",repo,"branch","--show-current"],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True)
 return {"repository":label,"present":True,"head":head.stdout.strip() if head.returncode==0 else None,"branch":branch.stdout.strip() if branch.returncode==0 else None,"entries":sorted(out,key=lambda x:(x["path"],x["status"],x.get("original_path") or ""))}

def save(path,obj):
 os.makedirs(os.path.dirname(path),exist_ok=True)
 fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),prefix=".tmp-",text=True)
 with os.fdopen(fd,"w",encoding="utf-8") as f:
  json.dump(obj,f,indent=2,sort_keys=True); f.write("\n"); f.flush(); os.fsync(f.fileno())
 os.replace(tmp,path)

def path_state(root,rel):
 full=os.path.join(root,rel)
 try: os.lstat(full)
 except FileNotFoundError: return {"path":rel,"type":"absent","signature":None}
 if os.path.islink(full):
  return {"path":rel,"type":"symlink","target":os.readlink(full),"signature":"symlink-sha256:"+hashlib.sha256(os.readlink(full).encode()).hexdigest()}
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
    p=os.path.join(base,name); r=os.path.relpath(p,full)
    h.update(r.encode("utf-8","surrogateescape")+b"\0")
    if os.path.islink(p): h.update(b"L\0"+os.readlink(p).encode("utf-8","surrogateescape"))
    elif os.path.isfile(p):
     h.update(b"F\0")
     with open(p,"rb") as f:
      for chunk in iter(lambda:f.read(1024*1024),b""): h.update(chunk)
    else: h.update(b"D\0")
  return {"path":rel,"type":"directory","signature":"tree-sha256:"+h.hexdigest()}
 return {"path":rel,"type":"other","signature":None}

root=sys.argv[1]
save(sys.argv[2],snap(root,"project")); save(sys.argv[3],snap(os.path.join(root,".private"),"private"))
protected=["AGENTS.md","CLAUDE.md","metadata-schema.json","skills-lock.json",".agents",".claude/skills"]
protected += ["scripts"] if os.path.islink(os.path.join(root,"scripts")) else ["scripts/cli-initialize.zsh","scripts/cli-pre-pass.zsh","scripts/cli-agent-runner.zsh","scripts/cli-post-pass.zsh","scripts/cli-log-collector.zsh","scripts/cli-commit.zsh","scripts/cli-push.zsh","scripts/cli-session-abort.zsh"]
private=[".private/AGENTS.md",".private/metadata-schema.json",".private/skills-lock.json",".private/workflow-templates/pass-report-template.md",".private/.agents/skills",".private/.agents/skills-store",".private/scripts"]
save(sys.argv[4],{"paths":[path_state(root,p) for p in protected+private]})' \
  "$AI_PROJECT_ROOT" "$pub" "$priv" "$protected_start" 2>>"$diagnostics" \
  || die 90 snapshot "cannot capture starting repository/control state; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"

if [[ -n "${AI_PRIOR_CONTINUATION_STATE_PATH:-}" ]]; then
  need_file "$AI_PRIOR_CONTINUATION_STATE_PATH" "prior finalized continuation state"
  local discrepancy_path="$AI_TMP_ROOT/runtime/continuation-discrepancies.json"

  python3 -c 'import json,sys,os,tempfile
prior=json.load(open(sys.argv[1],encoding="utf-8"))
prior_repositories=prior.get("repositories")
if isinstance(prior_repositories,list):
 expected={item.get("repository"):item for item in prior_repositories if isinstance(item,dict)}
else:
 expected=prior.get("ending_repository_state") or {}
actual={
 "project":json.load(open(sys.argv[2],encoding="utf-8")),
 "private":json.load(open(sys.argv[3],encoding="utf-8"))
}
diffs=[]
for repo in ("project","private"):
 exp=expected.get(repo)
 cur=actual[repo]
 if exp is None:
  diffs.append({"repository":repo,"rule":"missing-prior-state"})
  continue
 exp_entries={
  (x.get("status_type") or x.get("status"),x.get("path"),x.get("content_signature") or x.get("signature"))
  for x in exp.get("entries",[])
 }
 cur_entries={
  (x.get("status_type") or x.get("status"),x.get("path"),x.get("content_signature") or x.get("signature"))
  for x in cur.get("entries",[])
 }
 for entry in sorted(exp_entries-cur_entries,key=lambda x:(str(x[1]),str(x[0]),str(x[2]))):
  diffs.append({"repository":repo,"rule":"missing-or-changed-expected-entry","entry":entry})
 for entry in sorted(cur_entries-exp_entries,key=lambda x:(str(x[1]),str(x[0]),str(x[2]))):
  diffs.append({"repository":repo,"rule":"unexpected-or-changed-entry","entry":entry})
os.makedirs(os.path.dirname(sys.argv[4]),exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix=".tmp-",dir=os.path.dirname(sys.argv[4]),text=True)
with os.fdopen(fd,"w",encoding="utf-8") as f:
 json.dump({"discrepancies":diffs},f,indent=2,sort_keys=True)
 f.write("\n")
 f.flush()
 os.fsync(f.fileno())
os.replace(tmp,sys.argv[4])
raise SystemExit(1 if diffs else 0)' \
    "$AI_PRIOR_CONTINUATION_STATE_PATH" "$pub" "$priv" "$discrepancy_path" 2>>"$diagnostics" \
    || die 30 continuation "public/private continuation discrepancies recorded at ${discrepancy_path#$AI_PROJECT_ROOT/}; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"
elif [[ "${AI_FIRST_PASS:-0}" != 1 && "${AI_ALLOW_BASELINE_RECONCILIATION:-0}" != 1 ]]; then
  die 30 continuation "prior continuation state absent; explicitly mark a first pass or baseline reconciliation"
fi

AI_SKILL_STORE_PATH="${AI_SKILL_STORE_PATH:-$AI_PROJECT_ROOT/.private/.agents/skills-store}"
AI_SKILL_CATALOG_PATH="${AI_SKILL_CATALOG_PATH:-$AI_PROJECT_ROOT/.private/.agents/skills}"
AI_SKILLS_LOCK_PATH="${AI_SKILLS_LOCK_PATH:-$AI_PROJECT_ROOT/.private/skills-lock.json}"
AI_SKILL_ACTIVATION_EVIDENCE_PATH="${AI_SKILL_ACTIVATION_EVIDENCE_PATH:-${AI_RUNTIME_STATE_PATH:h}/skill-activation.json}"
inside "$AI_SKILL_STORE_PATH" "$AI_PROJECT_ROOT"
inside "$AI_SKILL_CATALOG_PATH" "$AI_PROJECT_ROOT"

skill_gate_program() {
  cat <<'CLI_SKILL_GATE_PY'
import hashlib,json,os,sys
store,catalog,lock_path=sys.argv[1:4]

def dir_hash(p):
    h=hashlib.sha256()
    for root,dirs,files in os.walk(p):
        dirs.sort()
        for name in sorted(files):
            fp=os.path.join(root,name)
            rel=os.path.relpath(fp,p)
            if os.path.islink(fp):
                return None,"symlink inside skill directory: "+rel
            h.update(rel.encode("utf-8")+b"\0")
            with open(fp,"rb") as f:
                for chunk in iter(lambda: f.read(65536), b""):
                    h.update(chunk)
            h.update(b"\n")
    return "sha256:"+h.hexdigest(),None

def frontmatter(p):
    fm={}
    try:
        with open(p,encoding="utf-8") as f:
            if f.readline().strip()!="---":
                return None
            for line in f:
                if line.strip()=="---":
                    break
                if ":" in line:
                    k,v=line.split(":",1)
                    fm[k.strip()]=v.strip().strip('"').strip("'")
    except OSError:
        return None
    return fm

REQUIRED=("name","version","status","source","directory_hash","invocation",
          "disable_model_invocation","allow_implicit_invocation","authorizing_pass",
          "authorizing_pass_type","authorization_finalized","evaluation_evidence_path",
          "evaluation_result","evaluation_directory_hash","last_passing_evaluation")

records={}
lock_error=None
if os.path.isfile(lock_path):
    try:
        for r in json.load(open(lock_path,encoding="utf-8")).get("skills",[]):
            if isinstance(r,dict) and r.get("name"):
                records[r["name"]]=r
    except (ValueError,OSError) as exc:
        lock_error="unreadable skills-lock.json: %s" % exc
else:
    lock_error="skills-lock.json is absent"

names=set()
if os.path.isdir(store):
    names |= {d for d in os.listdir(store)
              if os.path.isdir(os.path.join(store,d)) and not d.startswith(".")}
if os.path.isdir(catalog):
    names |= {d for d in os.listdir(catalog) if not d.startswith(".")}

out=[]
for name in sorted(names):
    sd=os.path.join(store,name)
    reasons=[]
    invocation=None
    computed=None
    if not os.path.isdir(sd):
        reasons.append("no authorized content in the skill store")
    if lock_error:
        reasons.append(lock_error)
    rec=records.get(name)
    if rec is None:
        reasons.append("no skills-lock.json record")
    if os.path.isdir(sd):
        computed,err=dir_hash(sd)
        if err:
            reasons.append(err)
    if rec is not None:
        missing=[k for k in REQUIRED if k not in rec]
        if missing:
            reasons.append("lock record is missing required fields: "+", ".join(missing))
        if rec.get("name")!=name:
            reasons.append("lock record identity does not match the installed directory name")
        if rec.get("status")!="active":
            reasons.append("lock record status is not active")
        if rec.get("revoked") is True:
            reasons.append("authorization was revoked")
        if rec.get("authorizing_pass_type")!="skill_bootstrap":
            reasons.append("authorization was not established by a dedicated skill_bootstrap pass")
        if rec.get("authorization_finalized") is not True:
            reasons.append("the authorizing skill_bootstrap pass did not complete successful workflow finalization")
        if rec.get("evaluation_result")!="passed":
            reasons.append("no passing evaluation evidence is recorded")
        if not rec.get("last_passing_evaluation"):
            reasons.append("no last passing evaluation is recorded")
        ev=rec.get("evaluation_evidence_path")
        if not ev:
            reasons.append("no evaluation evidence path is recorded")
        else:
            evp=ev if os.path.isabs(ev) else os.path.join(os.path.dirname(lock_path),ev)
            if not os.path.isfile(evp):
                reasons.append("recorded evaluation evidence is absent: "+str(ev))
        if computed is not None:
            if rec.get("directory_hash")!=computed:
                reasons.append("installed full-directory hash does not match the lock record")
            if rec.get("evaluation_directory_hash")!=computed:
                reasons.append("passing evaluation evidence does not identify the installed full-directory hash")
        invocation=rec.get("invocation")
    fm=frontmatter(os.path.join(sd,"SKILL.md")) if os.path.isdir(sd) else None
    if fm is None:
        reasons.append("SKILL.md frontmatter is absent or unreadable")
    elif rec is not None:
        if fm.get("name")!=name:
            reasons.append("SKILL.md frontmatter name does not match the directory identity")
        if fm.get("version")!=str(rec.get("version")):
            reasons.append("SKILL.md frontmatter version does not match the lock record")
        if fm.get("invocation")!=rec.get("invocation"):
            reasons.append("invocation mode disagrees between SKILL.md frontmatter and the lock record")
        if fm.get("disable-model-invocation")!=str(rec.get("disable_model_invocation")).lower():
            reasons.append("disable-model-invocation disagrees between SKILL.md frontmatter and the lock record")
        if fm.get("allow_implicit_invocation")!=str(rec.get("allow_implicit_invocation")).lower():
            reasons.append("allow_implicit_invocation disagrees between SKILL.md frontmatter and the lock record")
        if rec.get("invocation")=="auto" and not (
            rec.get("disable_model_invocation") is False and rec.get("allow_implicit_invocation") is True):
            reasons.append("auto invocation requires disable_model_invocation false and allow_implicit_invocation true")
        if rec.get("invocation")=="manual" and not (
            rec.get("disable_model_invocation") is True and rec.get("allow_implicit_invocation") is False):
            reasons.append("manual invocation requires disable_model_invocation true and allow_implicit_invocation false")
    out.append({"name":name,"active":not reasons,"invocation":invocation,
                "computed_directory_hash":computed,"reasons":reasons})

print(json.dumps({"evaluated_at_paths":{"store":store,"catalog":catalog,"lock":lock_path},
                  "skills":out},indent=2,sort_keys=True))
CLI_SKILL_GATE_PY
}

skill_gate_names() {
  python3 -c 'import json,sys
want=sys.argv[2]=="active"
print("\n".join(s["name"] for s in json.load(open(sys.argv[1],encoding="utf-8"))["skills"] if s["active"] is want))' "$1" "$2"
}

skill_gate_reconcile() {
  local store="$AI_SKILL_STORE_PATH" catalog="$AI_SKILL_CATALOG_PATH"
  local lock="$AI_SKILLS_LOCK_PATH" evidence="$AI_SKILL_ACTIVATION_EVIDENCE_PATH"
  local diagnostics="${AI_RUNTIME_STATE_PATH:h}/skill-gate-errors.log"
  mkdir -p -- "$store" "$catalog" "${evidence:h}" || die 40 skills "cannot create skill gate paths"
  skill_gate_program | python3 - "$store" "$catalog" "$lock" >| "$evidence" 2>>"$diagnostics" \
    || die 40 skills "skill authorization gate failed; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"

  local -a active_names inert_names
  active_names=("${(@f)$(skill_gate_names "$evidence" active)}")
  inert_names=("${(@f)$(skill_gate_names "$evidence" inert)}")
  active_names=("${(@)active_names:#}")
  inert_names=("${(@)inert_names:#}")

  local n link resolved
  for n in $inert_names; do
    link="$catalog/$n"
    if [[ -L "$link" ]]; then
      rm -f -- "$link" || die 40 skills "cannot deactivate unauthorized skill: $n"
      print -- "[$(now)] skill deactivated as inert: $n" >> "$AI_META_LOG_PATH" \
        || die 90 meta "cannot append skill deactivation evidence"
    elif [[ -e "$link" ]]; then
      die 40 skills "discoverable skill catalog contains non-symlink content that the authorization gate cannot govern: $n"
    fi
  done

  for n in $active_names; do
    link="$catalog/$n"
    if [[ -L "$link" ]]; then
      resolved="$(resolve_dir "$link")" || resolved=""
      [[ "$resolved" == "$store/$n" ]] \
        || die 40 skills "activated skill link resolves outside the authorized skill store: $n"
    elif [[ -e "$link" ]]; then
      die 40 skills "discoverable skill catalog contains non-symlink content that the authorization gate cannot govern: $n"
    else
      ln -s -- "../skills-store/$n" "$link" || die 40 skills "cannot activate authorized skill: $n"
      print -- "[$(now)] skill activated under current authorization evidence: $n" >> "$AI_META_LOG_PATH" \
        || die 90 meta "cannot append skill activation evidence"
    fi
  done

  local -a required missing
  required=("${(@s: :)${AI_REQUIRED_SKILLS:-}}")
  required=("${(@)required:#}")
  for n in $required; do
    (( ${active_names[(I)$n]} )) || missing+=("$n")
  done
  if (( ${#missing} )); then
    die 40 skills "the active prompt requires skills that are not authorized and are therefore inert: ${(j:, :)missing}; run a dedicated skill_bootstrap pass"
  fi
}

skill_gate_reconcile

local patch
patch="$(python3 -c 'import json,sys,datetime
print(json.dumps({"artifact_stem":sys.argv[1],"pass_id":sys.argv[2],"pre_pass_completed_at":datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),"agent_started":False,"runtime_identity":{"pass_id":sys.argv[2],"artifact_stem":sys.argv[1],"lifecycle_session_id":None,"launcher_pid":None,"launcher_process_start_marker":None,"capture_pid":None,"capture_process_start_marker":None,"code_agent_pid":None,"code_agent_binary":None,"code_agent_process_start_marker":None,"process_group_id":None,"raw_log_path":sys.argv[6],"registered_at":None,"active":False},"public_start_snapshot_path":sys.argv[3],"private_start_snapshot_path":sys.argv[4],"protected_workflow_start_path":sys.argv[5],"collector_control_path":sys.argv[7],"collector_state_path":sys.argv[8],"runner_control_path":sys.argv[9],"capture_process_exit_status":None,"code_agent_exit_status":None,"code_agent_exit_status_available":False,"code_agent_exit_status_source":None,"capture_status_contract_id":None,"termination_detail":None,"agent_exit_code":None,"agent_started_at":None,"agent_exited_at":None,"duration_seconds":None,"total_tokens_used":None,"metadata_format_version":"full-provisional-v1","normalized_telemetry_path":sys.argv[10],"metadata_evidence_index_path":None,"metadata_evidence_index_sha256":None,"runtime_seed_manifest_path":None if sys.argv[11]=="" else sys.argv[11],"seed_mode":sys.argv[12]=="true","runtime_seed_attribution_path":None if sys.argv[12]!="true" else sys.argv[13],"collector_exit_status":None,"collector_status":"pending","collector_clean_log_ready":False,"collector_completed_at":None}))' "$AI_ARTIFACT_STEM" "$AI_PASS_ID" "$pub" "$priv" "$protected_start" "$AI_RAW_LOG_PATH" "$AI_COLLECTOR_CONTROL_PATH" "$AI_COLLECTOR_STATE_PATH" "$AI_RUNNER_CONTROL_PATH" "$normalized_telemetry_rel" "$seed_manifest_rel" "$seed_mode" "${seed_attribution#$AI_PROJECT_ROOT/}" 2>>"$diagnostics")" || die 90 state "cannot encode pre-pass state; diagnostics retained at ${diagnostics#$AI_PROJECT_ROOT/}"
json_merge "$AI_RUNTIME_STATE_PATH" "$patch"
{
  print -- "[$(now)] pre-pass complete"
  print -- "artifact_stem=$AI_ARTIFACT_STEM"
  print -- "public_start_snapshot=${pub#$AI_PROJECT_ROOT/}"
  print -- "private_start_snapshot=${priv#$AI_PROJECT_ROOT/}"
  print -- "protected_workflow_start=${protected_start#$AI_PROJECT_ROOT/}"
} >> "$AI_META_LOG_PATH" || die 90 meta "cannot append pre-pass evidence"
print -- "Pre-pass ready: $AI_ARTIFACT_STEM"
