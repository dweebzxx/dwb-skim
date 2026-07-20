#!/usr/bin/env zsh
set -euo pipefail

script_dir="${0:A:h}"
dwb_dir="${script_dir:h}"
repo_root="${dwb_dir:h}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/dwb-skim-volume-normalizer.XXXXXX")"
trap 'rm -rf "${temporary_directory}"' EXIT

xcrun swiftc \
  "${dwb_dir}/dwb-skim/Player/VideoAudioNormalizationPolicy.swift" \
  "${script_dir}/VolumeNormalizerVerification.swift" \
  -o "${temporary_directory}/verify-volume-normalizer"

"${temporary_directory}/verify-volume-normalizer"
