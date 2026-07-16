#!/usr/bin/env zsh
set -euo pipefail

script_dir="${0:A:h}"
dwb_dir="${script_dir:h}"
repo_root="${dwb_dir:h}"
project_path="${dwb_dir}/dwb-skim.xcodeproj"
derived_data_path="${DWB_SKIM_TEST_DERIVED_DATA:-${repo_root}/.tmp/DerivedData-dwb-skim-tests}"

"${script_dir}/generate-project.zsh"

xcodebuild \
  -project "${project_path}" \
  -scheme "dwb-skimTests" \
  -configuration "Debug" \
  -destination "platform=macOS" \
  -derivedDataPath "${derived_data_path}" \
  clean build

xcodebuild \
  -project "${project_path}" \
  -scheme "dwb-skimTests" \
  -configuration "Debug" \
  -destination "platform=macOS" \
  -derivedDataPath "${derived_data_path}" \
  clean test

print "Built and tested: dwb-skimTests"
