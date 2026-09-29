#!/usr/bin/env bash
# One-time setup for a fresh clone: pinned tools, simulator runtimes, git hooks.
# Idempotent — safe to re-run. Needs the network on the first run only.
set -euo pipefail

cd "$(dirname "$0")/.."

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---- 1. Xcode ---------------------------------------------------------------
say "Xcode"
scripts/check-xcode-version.sh # check.sh step 0 runs the same check

# ---- 2. Pinned CLI tools ----------------------------------------------------
say "Tools (mise.toml)"
if ! command -v mise >/dev/null 2>&1; then
    echo "error: mise is not installed — 'brew install mise' then re-run." >&2
    exit 1
fi
mise install
mise ls

# ---- 3. Simulator runtimes --------------------------------------------------
# -downloadPlatform takes a *build* number, not a marketing version (iOS 27.0 =
# 24A434, watchOS 27.0 = 24R362), and Xcode 27.0 already ships with these as its
# defaults — so we download the platform and only warn if the version differs.
say "Simulator runtimes"
runtimes="$(xcrun simctl list runtimes)"
for platform in iOS:27.0 watchOS:27.0; do
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
xcrun simctl list devices available | grep -E "iPhone 17|Apple Watch Series 12" || cat <<MSG
No 'iPhone 17' / 'Apple Watch Series 12 (46mm)' simulator found. Create them in
Xcode ▸ Devices and Simulators, or override the destinations:
  export LEDGER_IOS_DEST='platform=iOS Simulator,name=<name>,OS=27.0'
  export LEDGER_WATCH_DEST='platform=watchOS Simulator,name=<name>,OS=27.0'
MSG

say "Bootstrap complete — run scripts/check.sh"
