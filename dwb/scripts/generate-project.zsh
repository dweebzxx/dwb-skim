#!/usr/bin/env zsh
set -euo pipefail

script_dir="${0:A:h}"
dwb_dir="${script_dir:h}"
repo_root="${dwb_dir:h}"
project_path="${dwb_dir}/dwb-skim.xcodeproj"
app_scheme="${project_path}/xcshareddata/xcschemes/dwb-skim.xcscheme"
tests_scheme="${project_path}/xcshareddata/xcschemes/dwb-skimTests.xcscheme"

if command -v xcodegen >/dev/null 2>&1; then
  cd "${dwb_dir}"
  xcodegen generate --spec project.yml
else
  print -u2 "warning: xcodegen not found; validating existing generated project only"
fi

[[ -d "${project_path}" ]] || {
  print -u2 "error: missing ${project_path}"
  exit 1
}

[[ -f "${app_scheme}" ]] || {
  print -u2 "error: missing ${app_scheme}"
  exit 1
}

[[ -f "${tests_scheme}" ]] || {
  print -u2 "error: missing ${tests_scheme}"
  exit 1
}

print "Project ready: ${project_path#${repo_root}/}"
