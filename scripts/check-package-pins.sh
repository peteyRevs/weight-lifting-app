#!/usr/bin/env bash
# Fails unless LedgerKit/Package.resolved pins exactly what the project's Package.resolved pins (F32).
# CI proves only the project's lockfile (cold, with -onlyUsePackageVersionsFromResolvedFile); LedgerKit's
# is read by `swift test` alone. LedgerKit is the project's only package root and the app targets add no
# package of their own (engineering-standards §1), so both files pin one graph and must agree on every
# package: identity, kind, location, version and revision. originHash may differ (Xcode 26.6 wrote two).
#
#   scripts/check-package-pins.sh   # used by check.sh step 2
set -euo pipefail

cd "$(dirname "$0")/.."
LEDGERKIT="LedgerKit/Package.resolved"
PROJECT="Ledger.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# One pin per line, keys sorted, in identity order. A missing file or one without pins fails here.
pins() { jq -S -c '.pins | sort_by(.identity) | .[]' "$1"; }
project_pins="$(pins "$PROJECT")"
ledgerkit_pins="$(pins "$LEDGERKIT")"

if [[ "$project_pins" != "$ledgerkit_pins" ]]; then
    diff -u --label "$PROJECT" --label "$LEDGERKIT" <(printf '%s\n' "$project_pins") \
        <(printf '%s\n' "$ledgerkit_pins") >&2 || true
    cat >&2 <<MSG

error: the two Package.resolved files pin different packages (above). Both must pin LedgerKit's graph:
       re-resolve the stale one (swift package --package-path LedgerKit resolve, or
       xcodebuild -resolvePackageDependencies for the project's), then commit both.
       The app targets may not add a package of their own (engineering-standards §1).
MSG
    exit 1
fi
echo "package pins agree: $LEDGERKIT and the project's Package.resolved ($(grep -c . <<<"$project_pins") pins)"
