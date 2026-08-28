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
  local diagnostics="${target:h}/cli-push-python-errors.log"
  mkdir -p -- "${target:h}" || die 90 receipt "cannot create receipt directory: ${target:h}"
  python3 -c 'import os,sys,tempfile
path,content=sys.argv[1],sys.argv[2]; directory=os.path.dirname(path) or "."
fd,tmp=tempfile.mkstemp(prefix="."+os.path.basename(path)+".tmp-",dir=directory,text=True)
with os.fdopen(fd,"w",encoding="utf-8") as f:
 f.write(content); f.flush(); os.fsync(f.fileno())
os.replace(tmp,path)' "$target" "$content" 2>>"$diagnostics" || die 90 receipt "cannot atomically write receipt: $target; diagnostics retained at $diagnostics"
}

local root="${AI_PROJECT_ROOT:-}"
local repo_sel=""
local remote=""
local source=""
local destination=""
local expected=""
local tag=""
local tag_message=""
local stem=""
AI_EXPECTED_REMOTE_URL="${AI_EXPECTED_REMOTE_URL:-}"

while (( $# )); do
  case "$1" in
    --project-root) (( $# >= 2 )) || die 2 input "missing value for --project-root"; root="$2"; shift 2;;
    --repository) (( $# >= 2 )) || die 2 input "missing value for --repository"; repo_sel="$2"; shift 2;;
    --remote) (( $# >= 2 )) || die 2 input "missing value for --remote"; remote="$2"; shift 2;;
    --expected-remote-url) (( $# >= 2 )) || die 2 input "missing value for --expected-remote-url"; AI_EXPECTED_REMOTE_URL="$2"; shift 2;;
    --source-ref) (( $# >= 2 )) || die 2 input "missing value for --source-ref"; source="$2"; shift 2;;
    --destination-ref) (( $# >= 2 )) || die 2 input "missing value for --destination-ref"; destination="$2"; shift 2;;
    --expected-commit) (( $# >= 2 )) || die 2 input "missing value for --expected-commit"; expected="$2"; shift 2;;
    --tag) (( $# >= 2 )) || die 2 input "missing value for --tag"; tag="$2"; shift 2;;
    --tag-message) (( $# >= 2 )) || die 2 input "missing value for --tag-message"; tag_message="$2"; shift 2;;
    --artifact-stem) (( $# >= 2 )) || die 2 input "missing value for --artifact-stem"; stem="$2"; shift 2;;
    *) die 2 input "unknown option: $1";;
  esac
done

[[ -n "$root" && -n "$repo_sel" && -n "$remote" && -n "$source" && -n "$destination" && -n "$expected" && -n "$stem" ]] || die 70 authorization "required: --project-root --repository --remote --source-ref --destination-ref --expected-commit --artifact-stem"
root="$(resolve_dir "$root")" || die 30 repository "cannot resolve project root"
[[ "$repo_sel" == project || "$repo_sel" == private ]] || die 70 authorization "invalid repository selection"
[[ "$stem" =~ $CLI_STEM_RE ]] || die 20 identity "invalid artifact stem: $stem"
local repo="$root"
[[ "$repo_sel" == private ]] && repo="$root/.private"
[[ -d "$repo/.git" ]] || die 30 repository "selected repository unavailable"

[[ -n "${AI_EXPECTED_REMOTE_URL:-}" ]] \
  || die 70 authorization "AI_EXPECTED_REMOTE_URL must contain the reviewed remote URL"

local actual_remote_url
actual_remote_url="$(git -C "$repo" remote get-url "$remote" 2>/dev/null)" \
  || die 10 remote "selected remote does not already exist: $remote"

[[ "$actual_remote_url" == "$AI_EXPECTED_REMOTE_URL" ]] \
  || die 30 remote "remote URL changed after review: expected $AI_EXPECTED_REMOTE_URL; found $actual_remote_url"

local resolved
resolved="$(git -C "$repo" rev-parse "$source^{commit}" 2>/dev/null)" \
  || die 30 ref "source ref is not a commit: $source"

[[ "$resolved" == "$expected" ]] \
  || die 30 identity "source ref no longer matches reviewed commit: expected $expected; found $resolved"

[[ "$destination" == refs/heads/* ]] \
  || die 70 ref "normal destination ref must be an explicit refs/heads/* ref"

if [[ -n "$tag" ]]; then
  [[ -n "$tag_message" ]] || die 70 tag "--tag-message is required when --tag is used"
  [[ "$tag" == refs/tags/* ]] || tag="refs/tags/$tag"
  [[ "$tag" != refs/tags/ ]] || die 70 tag "tag name is empty"
  git -C "$repo" show-ref --verify --quiet "$tag" \
    && die 30 tag "authorized tag already exists: $tag"
fi

git -C "$repo" push --no-force "$remote" "$source:$destination" \
  || die 30 push "explicit non-force ref push failed: $source:$destination"

if [[ -n "$tag" ]]; then
  git -C "$repo" tag -a "${tag#refs/tags/}" "$resolved" -m "$tag_message" \
    || die 30 tag "authorized local tag creation failed: $tag"

  git -C "$repo" push --no-force "$remote" "$tag:$tag" \
    || die 30 push "explicit non-force tag push failed: $tag"
fi

local receipt_root="$root/build-report-logs/tmp/$stem/human-actions"
local receipt="$receipt_root/push-$repo_sel.receipt"
local receipt_content
receipt_content="$(printf 'workflow_version=v2.4.1\ntimestamp=%s\nartifact_stem=%s\nrepository=%s\nremote=%s\nremote_url=%s\nsource_ref=%s\ndestination_ref=%s\ncommit=%s\ntag=%s\ntag_message=%s\n' "$(now)" "$stem" "$repo_sel" "$remote" "$actual_remote_url" "$source" "$destination" "$resolved" "$tag" "$tag_message")"
atomic_receipt "$receipt" "$receipt_content"
print -- "Push completed: $repo_sel $remote $source:$destination"
