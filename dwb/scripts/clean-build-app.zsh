#!/usr/bin/env zsh
set -euo pipefail

script_dir="${0:A:h}"
dwb_dir="${script_dir:h}"
repo_root="${dwb_dir:h}"
project_path="${dwb_dir}/dwb-skim.xcodeproj"
derived_data_path="${DWB_SKIM_DERIVED_DATA:-}"
derived_data_args=()
if [[ -n "${derived_data_path}" ]]; then
  derived_data_args=(-derivedDataPath "${derived_data_path}")
fi

"${script_dir}/generate-project.zsh"

xcodebuild \
  -project "${project_path}" \
  -scheme "dwb-skim" \
  -configuration "Debug" \
  -destination "platform=macOS" \
  "${derived_data_args[@]}" \
  clean build

if [[ -n "${derived_data_path}" ]]; then
  app_path="${derived_data_path}/Build/Products/Debug/dwb skim.app"
else
  build_settings="$(xcodebuild \
    -project "${project_path}" \
    -scheme "dwb-skim" \
    -configuration "Debug" \
    -destination "platform=macOS" \
    -showBuildSettings)"
  target_build_dir="$(print -r -- "${build_settings}" | sed -n 's/^ *TARGET_BUILD_DIR = //p' | head -n 1)"
  full_product_name="$(print -r -- "${build_settings}" | sed -n 's/^ *FULL_PRODUCT_NAME = //p' | head -n 1)"
  app_path="${target_build_dir}/${full_product_name}"
fi
[[ -d "${app_path}" ]] || {
  print -u2 "error: expected app artifact was not produced: ${app_path}"
  exit 1
}

print "Built app: ${app_path}"

dist_dir="${repo_root}/dist"
dist_app_path="${dist_dir}/dwb skim.app"

mkdir -p "${dist_dir}"
rm -rf "${dist_app_path}"
cp -R "${app_path}" "${dist_app_path}"

print "Dist app: ${dist_app_path}"
