#!/usr/bin/env bash
# scripts/check-catalog-version.sh (F03, fix round 1): a changed exercise catalog must raise
# ExerciseCatalog.version above main's, and catalog.version.sha never loses or edits a line main has.
# Each case builds a throwaway repository holding the three files the script reads and a copy of the
# real script, and runs it from another directory. No network: "origin" is a local clone.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

SCRIPT="${ADV_CHECK_CATALOG:-$ROOT/scripts/check-catalog-version.sh}" # override: mutation-test this suite
JSON=LedgerKit/Sources/LedgerDomain/Resources/exercises.json
HISTORY=LedgerKit/Sources/LedgerDomain/Resources/catalog.version.sha
SOURCE=LedgerKit/Sources/LedgerDomain/Catalog/ExerciseCatalog.swift

g() { git -C "$R" -c user.name=adv -c user.email=adv@example.invalid -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null "$@"; }
commit() { g add -A && g commit -q -m "$1"; }
set_version() { printf 'public enum ExerciseCatalog {\n    public static let version = %s\n}\n' "$1" >"$R/$SOURCE"; }
# catalog <id:name>...: the exercises, one {"id", "name"} object each.
catalog() {
    local entries=() pair
    for pair in "$@"; do entries+=("{\"id\": \"${pair%%:*}\", \"name\": \"${pair#*:}\"}"); done
    local IFS=,
    printf '{"exercises": [%s]}\n' "${entries[*]}" >"$R/$JSON"
}
# repo <name> [--no-source]: main holds catalog version 1 (or, with --no-source, only the JSON, as main
# did before F03); HEAD is a new branch "feature" off it. Sets $R.
repo() {
    R="$ADV_TMP/$1"
    mkdir -p "$R/scripts" "$R/$(dirname "$JSON")" "$R/$(dirname "$SOURCE")"
    cp "$SCRIPT" "$R/scripts/check-catalog-version.sh"
    g init -q -b main
    catalog 11:Bench
    if [[ "${2:-}" != --no-source ]]; then
        set_version 1
        printf '# SHA-256 per version\n1 aaaa\n' >"$R/$HISTORY"
    fi
    commit "catalog v1"
    g checkout -q -b feature
}
run() { # the script, from outside the repository: sets $code and $out
    out="$(cd "$ADV_TMP" && "$R/scripts/check-catalog-version.sh" 2>&1)"
    code=$?
}

repo unchanged && run
check "CV01 an unchanged catalog passes and says so" is "$code $(grep -c 'unchanged since main' <<<"$out")" "0 1"

repo same-version && catalog 11:Bench 22:Squat && run
line="2 $(shasum -a 256 "$R/$JSON" | cut -d' ' -f1)"
check "CV02 a changed catalog at the same version fails, printing the exact history line to add (uncommitted edits count)" \
    is "$code $(grep -c 'still 1' <<<"$out") $(grep -c 'Raise it to 2' <<<"$out") $(grep -cx "$line" <<<"$out")" "1 1 1 1"

repo bumped && catalog 11:Bench 22:Squat && set_version 2 && printf '2 bbbb\n' >>"$R/$HISTORY" && run
check "CV03 a changed catalog with the version raised passes" is "$code $(grep -c 'version 1 -> 2' <<<"$out")" "0 1"

repo committed && catalog 11:Bench 22:Squat && commit "change the catalog" && run
check "CV04 a committed change at the same version fails too" is "$code" 1

repo skip && catalog 11:Bench 22:Squat && set_version 3 && run
check "CV05 raising the version by more than one passes" is "$code" 0

repo fell && set_version 0 && run
check "CV06 a version below main's fails, even with the catalog unchanged" \
    is "$code $(grep -c 'fell from 1' <<<"$out")" "1 1"

repo no-base && g branch -q -m main trunk && run
check "CV07 no origin/main and no main: exit 2 with a clear message" \
    is "$code $(grep -c 'no origin/main or main' <<<"$out")" "2 1"

repo unrelated && g checkout -q --orphan lonely && commit "unrelated history" && run
check "CV08 a HEAD that shares no history with main: exit 2 with a clear message" \
    is "$code $(grep -c 'shares no history' <<<"$out")" "2 1"

repo no-source --no-source && catalog 11:Bench 22:Squat && set_version 1 && printf '1 aaaa\n' >"$R/$HISTORY" && run
check "CV09 main before ExerciseCatalog existed counts as version 0: version 1 passes" \
    is "$code $(grep -c 'version 0 -> 1' <<<"$out")" "0 1"

repo unreadable && printf 'public enum ExerciseCatalog {}\n' >"$R/$SOURCE" && run
check "CV10 a version the script cannot read: exit 2" is "$code $(grep -c "no 'public static let version" <<<"$out")" "2 1"

repo edited && catalog 11:Bench 22:Squat && set_version 2 && printf '# SHA-256 per version\n1 abab\n2 bbbb\n' >"$R/$HISTORY" && run
check "CV11 editing a line main has in catalog.version.sha fails, even with the version raised" \
    is "$code $(grep -c 'never edit a merged line' <<<"$out")" "1 1"

repo dropped && catalog 11:Bench 22:Squat && set_version 2 && printf '2 bbbb\n' >"$R/$HISTORY" && run
check "CV12 dropping a line main has fails" is "$code" 1

repo deleted && rm "$R/$HISTORY" && run
check "CV13 deleting catalog.version.sha fails" is "$code $(grep -c 'is gone' <<<"$out")" "1 1"

repo extended && catalog 11:Bench 22:Squat && set_version 2 && printf '# SHA-256 per version\n1 aaaab\n2 bbbb\n' >"$R/$HISTORY" && run
check "CV14 extending a merged line in place fails (a prefix is not the same line)" is "$code" 1

repo comments && printf '# reworded header\n\n1 aaaa\n' >"$R/$HISTORY" && run
check "CV15 comments and blank lines in catalog.version.sha may change" is "$code" 0

# CI's case: origin/main is ahead of the local main. The base must be origin/main's: against the stale
# main, the branch's version 2 would look like a rise.
repo upstream
R_UP="$R" && g checkout -q main && catalog 11:Bench 22:Squat && set_version 2 && printf '2 bbbb\n' >>"$R/$HISTORY" &&
    commit "catalog v2 on main"
R="$ADV_TMP/clone" && git clone -q "$R_UP" "$R" && g checkout -q -b stale-main origin/main~1 &&
    g branch -q -f main stale-main && g checkout -q -b pr origin/main && catalog 11:Bench 22:Squat 33:Deadlift && run
check "CV16 origin/main wins over a stale local main: a change at origin/main's version fails" \
    is "$code $(grep -c 'differs from origin/main' <<<"$out")" "1 1"
set_version 3 && printf '3 cccc\n' >>"$R/$HISTORY" && run
check "CV17 ... and passes once raised above origin/main's" is "$code $(grep -c 'version 2 -> 3' <<<"$out")" "0 1"

# Ids (review S3): every id main has stays, on the entry it names, whatever the version says.
# bumped <name>: a repository whose main has Bench (11) and Squat (22), version 1; the branch is at version 2.
bumped() {
    repo "$1" && g checkout -q main && catalog 11:Bench 22:Squat && commit "two entries" &&
        g checkout -q -B feature && set_version 2
}
bumped rerolled && catalog 11:Bench 99:Squat && run
check "CV18 a re-rolled id (same entry, new id) fails even with the version raised, naming both ids" \
    is "$code $(grep -c 'Squat was 22 and is now 99' <<<"$out")" "1 1"
bumped deleted-entry && catalog 11:Bench && run
check "CV19 a deleted entry fails: its id is gone" is "$code $(grep -c '22 (Squat) is gone' <<<"$out")" "1 1"
bumped swapped && catalog 22:Bench 11:Squat && run
check "CV20 two entries that swap ids fail" is "$code $(grep -c 'was' <<<"$out")" "1 2"
bumped renamed && catalog 11:Bench 22:"Back Squat" 33:Lunge && run
check "CV21 renaming an entry and adding one, with every id kept, passes" is "$code" 0

finish
