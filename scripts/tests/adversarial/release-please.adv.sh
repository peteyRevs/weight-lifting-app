#!/usr/bin/env bash
# release-please config, manifest and the MARKETING_VERSION marker must agree, or the
# release PR bumps nothing, bumps the wrong line, or tags what Xcode Cloud ignores.
# release-please itself needs the GitHub API, so its behaviour is not executed here;
# these are the static preconditions for criteria 8 and 9.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

CONFIG="$ROOT/release-please-config.json"
MANIFEST="$ROOT/.release-please-manifest.json"
BASE="$ROOT/Config/Base.xcconfig"
is() { [[ "$1" == "$2" ]] || { printf 'got: %s\nwant: %s\n' "$1" "$2"; return 1; }; }

check "RP01 config and manifest are valid JSON" jq -e . "$CONFIG" "$MANIFEST"

markers="$(grep -c 'x-release-please-version' "$BASE")"
line="$(grep 'x-release-please-version' "$BASE" | head -1)"
check "RP02 Base.xcconfig has exactly one version marker" is "$markers" 1
check "RP03 the marker sits on the MARKETING_VERSION assignment" \
    grep -qE '^MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+ // x-release-please-version$' <<<"$line"
check "RP04 the marker line holds exactly one version (the updater rewrites every one)" \
    is "$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$line" | wc -l | tr -d ' ')" 1
check "RP05 manifest version equals MARKETING_VERSION" \
    is "$(jq -r '."."' "$MANIFEST")" "$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$line")"

extra="$(jq -r '.packages["."]["extra-files"][] | if type == "string" then . else .path end' "$CONFIG" | sort)"
marked="$(cd "$ROOT" && git ls-files | grep -vE '\.md$|^release-please-config\.json$' \
    | xargs grep -l 'x-release-please-' 2>/dev/null | sort)"
check "RP06 every file carrying a marker is an extra-file, and every extra-file has one" is "$marked" "$extra"
check "RP07 the extra-file uses the generic updater" \
    is "$(jq -r '.packages["."]["extra-files"][0].type' "$CONFIG")" generic

check "RP08 tags are vX.Y.Z (no component, v kept) for Xcode Cloud's 'v' tag rule" \
    is "$(jq -r '[."release-type", (."include-component-in-tag" | tostring), ((."include-v-in-tag" // true) | tostring), (.packages["."].component // "none")] | join(" ")' "$CONFIG")" \
    "simple false true none"
check "RP09 feat bumps the minor pre-1.0 (0.1.0 -> 0.2.0, criterion 8)" \
    is "$(jq -r '[(."bump-minor-pre-major" | tostring), ((."bump-patch-for-minor-pre-major" // false) | tostring)] | join(" ")' "$CONFIG")" \
    "true false"
check "RP10 the changelog shows feat, fix, perf and hides everything else" \
    is "$(jq -r '[."changelog-sections"[] | select(.hidden != true) | .type] | sort | join(",")' "$CONFIG")" "feat,fix,perf"

sha="$(jq -r '."bootstrap-sha"' "$CONFIG")"
check "RP11 bootstrap-sha is an ancestor of HEAD" git -C "$ROOT" merge-base --is-ancestor "$sha" HEAD

overrides="$(cd "$ROOT" && grep -lE '^\s*MARKETING_VERSION\s*=' Config/*.xcconfig | grep -v '^Config/Base.xcconfig$' || true)
$(grep -c 'MARKETING_VERSION' "$ROOT/Ledger.xcodeproj/project.pbxproj" | grep -v '^0$' || true)"
check "RP12 nothing overrides MARKETING_VERSION after Base.xcconfig" is "$(echo $overrides)" ""

# The commit-msg hook must accept every type the changelog lists, or it cannot be written.
for type in $(jq -r '."changelog-sections"[].type' "$CONFIG"); do
    printf '%s: probe\n' "$type" >"$ADV_TMP/msg"
    check "RP13 commit-msg hook accepts '$type:'" "$ROOT/scripts/check-commit-msg.sh" "$ADV_TMP/msg"
done

finish
