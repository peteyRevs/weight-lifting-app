#!/usr/bin/env bash
# Fails unless the selected Xcode is the one .xcode-version pins. bootstrap.sh (step 1) and
# check.sh (step 0, every mode) both call it, so a machine or runner on another Xcode fails the
# gate at once instead of building with the wrong SDK.
set -euo pipefail

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
