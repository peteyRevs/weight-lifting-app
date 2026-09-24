#!/usr/bin/env bash
# One-time setup for a fresh clone: pinned tools, simulator runtimes, git hooks.
# Idempotent — safe to re-run. Needs the network on the first run only.
set -euo pipefail

cd "$(dirname "$0")/.."

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---- 1. Xcode ---------------------------------------------------------------
say "Xcode"
PINNED_XCODE="$(tr -d '[:space:]' < .xcode-version)"
ACTUAL_XCODE="$(xcodebuild -version | head -1 | awk '{print $2}')"
if [[ "$ACTUAL_XCODE" != "$PINNED_XCODE" ]]; then
    cat >&2 <<MSG
error: this repo is pinned to Xcode $PINNED_XCODE (.xcode-version) but
       xcodebuild reports $ACTUAL_XCODE.
       Select the right one:  sudo xcode-select -s /Applications/Xcode.app
MSG
    exit 1
fi
echo "Xcode $ACTUAL_XCODE ✓"

# ---- 2. Pinned CLI tools ----------------------------------------------------
say "Tools (mise.toml)"
if ! command -v mise >/dev/null 2>&1; then
    echo "error: mise is not installed — 'brew install mise' then re-run." >&2
    exit 1
fi
mise install
mise ls

# ---- 3. Simulator runtimes --------------------------------------------------
# -downloadPlatform takes a *build* number, not a marketing version (iOS 26.5 =
# 23F77, watchOS 26.5 = 23T570), and Xcode 26.6 already ships with these as its
# defaults — so we download the platform and only warn if the version differs.
say "Simulator runtimes"
runtimes="$(xcrun simctl list runtimes)"
for platform in iOS:26.5 watchOS:26.5; do
    name="${platform%%:*}"
    version="${platform##*:}"
    if grep -q "^$name $version" <<<"$runtimes"; then
        echo "$name $version runtime ✓"
    else
        echo "$name $version runtime missing — downloading (5–8 GB, slow)…"
        xcodebuild -downloadPlatform "$name"
    fi
done

# ---- 4. Git hooks -----------------------------------------------------------
say "Git hooks"
mise exec -- lefthook install

# ---- 5. What check.sh will target ------------------------------------------
say "Simulators available to scripts/check.sh"
xcrun simctl list devices available | grep -E "iPhone 17|Apple Watch Series 11" || cat <<MSG
No 'iPhone 17' / 'Apple Watch Series 11 (46mm)' simulator found. Create them in
Xcode ▸ Devices and Simulators, or override the destinations:
  export LEDGER_IOS_DEST='platform=iOS Simulator,name=<name>,OS=26.5'
  export LEDGER_WATCH_DEST='platform=watchOS Simulator,name=<name>,OS=26.5'
MSG

say "Bootstrap complete — run scripts/check.sh"
