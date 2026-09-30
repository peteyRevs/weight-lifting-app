#!/usr/bin/env bash
# Fails unless the selected Xcode is the one .xcode-version pins. bootstrap.sh (step 1) and
# check.sh (step 0, every mode) both call it, so a machine or runner on another Xcode fails the
# gate at once instead of building with the wrong SDK. It compares the version only, so a 27.0 beta
# or RC, which reports 27.0 too, passes: the build number is not pinned (F32 T3).
set -euo pipefail

# Whitespace and a CRLF are stripped, as the workflows' Select steps strip them (F32 T4).
PINNED_XCODE="$(tr -d '[:space:]' < "$(dirname "$0")/../.xcode-version")"
# awk reads all of xcodebuild's output; `head -1` could exit first and, under
# pipefail, SIGPIPE xcodebuild and abort the script (seen 1 run in 40).
ACTUAL_XCODE="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
if [[ "$ACTUAL_XCODE" != "$PINNED_XCODE" ]]; then
    cat >&2 <<MSG
error: this repo is pinned to Xcode $PINNED_XCODE (.xcode-version) but
       xcodebuild reports $ACTUAL_XCODE.
       Select the right one:  sudo xcode-select -s /Applications/Xcode.app
MSG
    exit 1
fi
echo "Xcode $ACTUAL_XCODE ✓"
