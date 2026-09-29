#!/usr/bin/env bash
# ci_scripts/ci_post_clone.sh: Xcode Cloud runs it from ci_scripts/ after cloning;
# it must set CURRENT_PROJECT_VERSION = CI_BUILD_NUMBER for BOTH apps (criterion 7)
# and refuse to write a build number App Store Connect would reject.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

SCRIPT="$ROOT/ci_scripts/ci_post_clone.sh"
T="$ADV_TMP"

# clone: a fresh copy of what the script and xcodebuild read, as Xcode Cloud clones it.
clone() {
    rm -rf "$T/repo"; mkdir -p "$T/repo"
    (cd "$ROOT" && rsync -a --exclude .build Ledger.xcodeproj Config Apps LedgerKit TestPlans ci_scripts "$T/repo/") ||
        exit 1 # a partial copy is not what Xcode Cloud clones
}
# post_clone [VAR=value...]: runs the real script from ci_scripts/ with only these CI vars.
post_clone() {
    out="$(cd "$T/repo/ci_scripts" && env -u CI_BUILD_NUMBER -u CI_PRIMARY_REPOSITORY_PATH \
        CI_PRIMARY_REPOSITORY_PATH="$T/repo" "$@" "$SCRIPT" 2>&1)"
    code=$?
}
# effective: CURRENT_PROJECT_VERSION as xcconfig reads Base.xcconfig (last assignment wins).
effective() {
    awk '/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*(\/\/.*)?$/, ""); v = $0 } END { print v }' \
        "$T/repo/Config/Base.xcconfig"
}
unchanged() { cmp -s "$ROOT/Config/Base.xcconfig" "$T/repo/Config/Base.xcconfig"; }

clone; post_clone CI_BUILD_NUMBER=42
check "PC01 build 42 -> CURRENT_PROJECT_VERSION = 42" is "$code $(effective)" "0 42"
check "PC02 MARKETING_VERSION is untouched" \
    is "$(grep MARKETING_VERSION "$T/repo/Config/Base.xcconfig")" "$(grep MARKETING_VERSION "$ROOT/Config/Base.xcconfig")"
post_clone CI_BUILD_NUMBER=42
check "PC03 running twice is harmless (still 42)" is "$code $(effective)" "0 42"

clone; post_clone
check "PC04 CI_BUILD_NUMBER unset -> fails, writes nothing" bash -c "[[ $code -ne 0 ]] && cmp -s '$ROOT/Config/Base.xcconfig' '$T/repo/Config/Base.xcconfig'"
clone; post_clone CI_BUILD_NUMBER=
check "PC05 CI_BUILD_NUMBER empty -> fails, writes nothing" bash -c "[[ $code -ne 0 ]] && cmp -s '$ROOT/Config/Base.xcconfig' '$T/repo/Config/Base.xcconfig'"
clone
out="$(cd "$T/repo/ci_scripts" && env -u CI_PRIMARY_REPOSITORY_PATH CI_BUILD_NUMBER=42 "$SCRIPT" 2>&1)"; code=$?
check "PC06 CI_PRIMARY_REPOSITORY_PATH unset -> fails, writes nothing" \
    bash -c "[[ $code -ne 0 ]] && cmp -s '$ROOT/Config/Base.xcconfig' '$T/repo/Config/Base.xcconfig'"

# CFBundleVersion must be one to three period-separated integers.
for bad in abc "1.2.3.4" "$(printf '5\nDEVELOPMENT_TEAM = ATTACKER')"; do
    clone; post_clone CI_BUILD_NUMBER="$bad"
    if [[ $code -ne 0 ]] && unchanged; then
        pass "PC07 non-numeric build number '${bad%%$'\n'*}…' is refused"
    else
        fail "PC07 [F8] non-numeric build number '${bad%%$'\n'*}…' is refused" \
            "exit $code; Base.xcconfig now ends: $(tail -2 "$T/repo/Config/Base.xcconfig" | tr '\n' '|')"
    fi
done

clone
printf '%s' "$(cat "$T/repo/Config/Base.xcconfig")" >"$T/repo/Config/Base.xcconfig" # drop the final newline
post_clone CI_BUILD_NUMBER=77
check "PC08 Base.xcconfig without a final newline still gets its own line" \
    is "$code $(effective) $(grep -c 'x-release-please-version$' "$T/repo/Config/Base.xcconfig")" "0 77 1"

check "PC09 the script is committed executable (Xcode Cloud skips it otherwise)" \
    is "$(git -C "$ROOT" ls-files -s ci_scripts/ci_post_clone.sh | awk '{ print $1 }')" 100755

# Both apps inherit the value: only Base.xcconfig sets it, and it is project-level.
others="$(cd "$ROOT" && grep -lE '^\s*CURRENT_PROJECT_VERSION\s*=' Config/*.xcconfig | grep -v 'Base.xcconfig' || true)"
check "PC10 no other xcconfig sets CURRENT_PROJECT_VERSION" is "$others" ""
check "PC11 the pbxproj sets no version, and Info.plists hardcode none" \
    is "$(cat "$ROOT/Ledger.xcodeproj/project.pbxproj" "$ROOT"/Apps/*.plist | grep -cE 'CURRENT_PROJECT_VERSION|CFBundleVersion')" 0

if command -v xcodebuild >/dev/null; then
    clone; post_clone CI_BUILD_NUMBER=4242
    got=""
    for scheme in Ledger LedgerWatch; do
        got="$got$(cd "$T/repo" && xcodebuild -showBuildSettings -project Ledger.xcodeproj -scheme "$scheme" \
            -configuration Release -clonedSourcePackagesDirPath "$T/packages" -disableAutomaticPackageResolution \
            -skipPackageUpdates 2>/dev/null | awk -v s="$scheme" '/^Build settings for action build and target/ { t = $NF; sub(/:$/, "", t) }
                t == s && $1 == "CURRENT_PROJECT_VERSION" { print t "=" $3 }')"
    done
    check "PC12 xcodebuild resolves 4242 for Ledger and LedgerWatch (Release)" \
        is "$got" "Ledger=4242LedgerWatch=4242"
    # SwiftPM leaves lock files named after the packages path in $TMPDIR.
    rm -f "${TMPDIR:-/tmp}"/*"$(basename "$T")"_packages_*.lock
else
    skip "PC12 xcodebuild -showBuildSettings for both apps" "no xcodebuild"
fi

finish
