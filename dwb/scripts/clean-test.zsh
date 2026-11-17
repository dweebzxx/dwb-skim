#!/usr/bin/env zsh
set -euo pipefail

script_dir="${0:A:h}"
dwb_dir="${script_dir:h}"
repo_root="${dwb_dir:h}"
project_path="${dwb_dir}/dwb-skim.xcodeproj"
derived_data_path="${DWB_SKIM_TEST_DERIVED_DATA:-}"
derived_data_args=()
if [[ -n "${derived_data_path}" ]]; then
  derived_data_args=(-derivedDataPath "${derived_data_path}")
fi

"${script_dir}/generate-project.zsh"

xcodebuild \
  -project "${project_path}" \
  -scheme "dwb-skimTests" \
  -configuration "Debug" \
  -destination "platform=macOS" \
  "${derived_data_args[@]}" \
  clean build

xcodebuild \
  -project "${project_path}" \
  -scheme "dwb-skimTests" \
  -configuration "Debug" \
  -destination "platform=macOS" \
  "${derived_data_args[@]}" \
  clean test

print "Built and tested: dwb-skimTests"
