#!/usr/bin/env zsh
set -euo pipefail

script_dir="${0:A:h}"
dwb_dir="${script_dir:h}"
repo_root="${dwb_dir:h}"
project_path="${dwb_dir}/dwb-skim.xcodeproj"
derived_data_path="${DWB_SKIM_DERIVED_DATA:-${repo_root}/.tmp/DerivedData-dwb-skim-app}"

"${script_dir}/generate-project.zsh"

xcodebuild \
  -project "${project_path}" \
  -scheme "dwb-skim" \
  -configuration "Debug" \
  -destination "platform=macOS" \
  -derivedDataPath "${derived_data_path}" \
  clean build

app_path="${derived_data_path}/Build/Products/Debug/dwb - skim.app"
[[ -d "${app_path}" ]] || {
  print -u2 "error: expected app artifact was not produced: ${app_path}"
  exit 1
}

print "Built app: ${app_path}"

dist_dir="${repo_root}/dist"
dist_app_path="${dist_dir}/dwb - skim.app"

mkdir -p "${dist_dir}"
rm -rf "${dist_app_path}"
cp -R "${app_path}" "${dist_app_path}"

print "Dist app: ${dist_app_path}"
