#!/usr/bin/env bash
# F03 adversarial (test engineer): scripts/check-catalog-version.sh against real git histories —
# the first introduction, unbumped and bumped edits (committed and uncommitted), history tampering,
# a CI-style detached merge commit, and shallow clones; since the close-out (round 2), the id guard
# (ids removed, re-rolled, swapped or duplicated, on CI's checkouts too). Written from the F03 brief
# (criterion 7 and its 2026-09-30 extension) and the script's own header. Bash 3.2, no network.
# needs macOS: V10 edits a file with BSD sed (sed -i ''), which GNU sed reads as a script.
set -uo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

SCRIPT="${ADV_CHECK_CATALOG:-$ROOT/scripts/check-catalog-version.sh}" # override: mutation-test this suite
J=LedgerKit/Sources/LedgerDomain/Resources/exercises.json
H=LedgerKit/Sources/LedgerDomain/Resources/catalog.version.sha
S=LedgerKit/Sources/LedgerDomain/Catalog/ExerciseCatalog.swift
REPO=""

g() { git -C "$REPO" -c user.name=adv -c user.email=adv@example.invalid -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null "$@"; }
commit() { g add -A && g commit -qm "$1"; }

# new_repo <dir> [placeholder|absent]: main as it was before F03, with the script.
new_repo() {
    REPO="$1"
    mkdir -p "$REPO/scripts" "$REPO/$(dirname "$J")" "$REPO/$(dirname "$S")"
    git init -q -b main "$REPO"
    cp "$SCRIPT" "$REPO/scripts/check-catalog-version.sh"
    if [[ "${2:-placeholder}" == placeholder ]]; then printf '{"version":1,"exercises":[]}' >"$REPO/$J"; fi
    commit base
}
set_version() { printf 'public enum ExerciseCatalog {\n    public static let version = %s\n}\n' "$1" >"$REPO/$S"; }
set_json() { printf '{"exercises":[%s]}\n' "$1" >"$REPO/$J"; }
sha() { shasum -a 256 "$REPO/$J" | cut -d' ' -f1; }
history() { printf '# header\n' >"$REPO/$H"; }
append_history() { printf '%s %s\n' "$1" "$(sha)" >>"$REPO/$H"; }
# run: the script's exit status; its output goes to $ADV_TMP/out. Run from elsewhere on purpose.
run() { (cd "$ADV_TMP" && bash "$REPO/scripts/check-catalog-version.sh") >"$ADV_TMP/out" 2>&1; echo $?; }
out() { cat "$ADV_TMP/out"; }

# introduce <n>: the F03 PR on branch feat — catalog, version n, history lines 1…n.
introduce() {
    g checkout -qb feat
    set_json '{"n":"A"}'
    set_version "$1"
    history
    local v
    for ((v = 1; v <= $1; v++)); do append_history "$v"; done
    commit "catalog v$1"
}

# ---- first introduction -----------------------------------------------------------------------
new_repo "$ADV_TMP/intro"
introduce 2
expect_exit "V01 first introduction over main's placeholder JSON (no ExerciseCatalog.swift at base) passes" 0 "$(run)" "$(out)"
check "V01b it reports the rise from 0" grep -q "version 0 -> 2" "$ADV_TMP/out"

new_repo "$ADV_TMP/absent" absent
introduce 1
expect_exit "V02 first introduction when exercises.json is absent at the base passes" 0 "$(run)" "$(out)"

new_repo "$ADV_TMP/zero"
introduce 1
set_version 0
commit "version 0"
expect_exit "V03 first introduction at version 0 (no rise above 'none') fails" 1 "$(run)" "$(out)"

# ---- after the merge: main has version 2 -------------------------------------------------------
new_repo "$ADV_TMP/m"
introduce 2
g checkout -q main && g merge -q --ff-only feat && g branch -qD feat
expect_exit "V04 main itself (HEAD is the base: nightly) passes as unchanged" 0 "$(run)" "$(out)"

g checkout -qb edit
set_json '{"n":"B"}'
expect_exit "V05 an uncommitted JSON edit at the same version fails" 1 "$(run)" "$(out)"
commit "edit"
expect_exit "V06 a committed JSON edit at the same version fails" 1 "$(run)" "$(out)"
check "V06b the message names the version to raise to" grep -q "Raise it to 3" "$ADV_TMP/out"
printf ' ' >>"$REPO/$J"
commit "whitespace"
expect_exit "V07 a whitespace-only edit also needs a bump (the SHA changes)" 1 "$(run)" "$(out)"

set_version 3
append_history 3
commit "bump"
expect_exit "V08 the same edit with version 3 and an appended history line passes" 0 "$(run)" "$(out)"

set_version 5
commit "skip"
expect_exit "V09 a jump of more than one version still passes (the history test pins the last line)" 0 "$(run)" "$(out)"
set_version 3
commit "back"

cp "$REPO/$H" "$ADV_TMP/h.keep"
sed -i '' 's/^1 [0-9a-f]*$/1 '"$(printf '%064d' 0)"'/' "$REPO/$H"
expect_exit "V10 editing a line main has (version 1's SHA) fails" 1 "$(run)" "$(out)"
cp "$ADV_TMP/h.keep" "$REPO/$H"
{ printf '# header\n'; grep -v '^#' "$ADV_TMP/h.keep" | awk 'NR == 1 { first = $0; next } NR == 2 { print; print first; next } { print }'; } >"$REPO/$H"
expect_exit "V11 reordering the lines main has fails" 1 "$(run)" "$(out)"
grep -v '^1 ' "$ADV_TMP/h.keep" >"$REPO/$H"
expect_exit "V12 dropping a line main has fails" 1 "$(run)" "$(out)"
rm "$REPO/$H"
expect_exit "V13 deleting the history file fails" 1 "$(run)" "$(out)"
{ printf '# a reworded header\n\n'; grep -v '^#' "$ADV_TMP/h.keep"; } >"$REPO/$H"
expect_exit "V14 rewording comments and adding blank lines is allowed" 0 "$(run)" "$(out)"
cp "$ADV_TMP/h.keep" "$REPO/$H"

set_version 1
expect_exit "V15 a version below main's fails even with the JSON otherwise bumped" 1 "$(run)" "$(out)"
set_version 3

# ---- CI: detached HEAD at the PR's merge commit, origin/main from a full fetch --------------------
g checkout -q main && g checkout -qb late
set_json '{"n":"C"}'
commit "unbumped edit"
ORIGIN="$ADV_TMP/origin.git"
git clone -q --bare "$REPO" "$ORIGIN"
CI="$ADV_TMP/ci"
git clone -q "$ORIGIN" "$CI"
REPO="$CI"
g checkout -q --detach origin/main
g merge -q --no-ff --no-edit origin/late
expect_exit "V16 CI's detached merge commit with an unbumped edit fails" 1 "$(run)" "$(out)"
g checkout -q --detach origin/main
g merge -q --no-ff --no-edit origin/edit
expect_exit "V17 CI's detached merge commit with a bumped edit passes" 0 "$(run)" "$(out)"
check "V17b it compared against origin/main" grep -q "since origin/main" "$ADV_TMP/out"

# ---- shallow clones fail closed (exit 2), never pass ------------------------------------------------
REPO="$ADV_TMP/shallow1"
git clone -q --depth 1 --branch late "file://$ORIGIN" "$REPO"
expect_exit "V18 a depth-1 clone of the branch alone (no main at all) fails closed" 2 "$(run)" "$(out)"
REPO="$ADV_TMP/shallow2"
git clone -q --depth 1 --no-single-branch --branch late "file://$ORIGIN" "$REPO"
expect_exit "V19 a depth-1 clone with a shallow origin/main (no shared history) fails closed" 2 "$(run)" "$(out)"

# ---- the version line the script reads ----------------------------------------------------------
REPO="$ADV_TMP/m"
g checkout -q edit
printf 'public enum ExerciseCatalog {\n    public static let version = 3 // bumped for F99\n}\n' >"$REPO/$S"
expect_exit "V20 a trailing comment on the version line fails closed (exit 2), not open" 2 "$(run)" "$(out)"
printf 'public enum ExerciseCatalog {\n    /// public static let version = 9\n    public static let version = 3\n}\n' >"$REPO/$S"
expect_exit "V21 a doc comment quoting an older version line is not read as the version" 0 "$(run)" "$(out)"

# ---- ids (fix round 2, review S3): every id main has stays on its entry, whatever the version says -----
# Entries are written as exercises.json writes them (one key per line, a one-line startLoad).
A=270DE1C9-481F-4904-BE85-070381E296C0 B=B33B4312-860A-456A-80BE-AFE2A7DFE844 C=AEB824D6-5758-4481-8C9F-A926070F3D5B
N=5A0E1F7C-3B2D-4C8E-9F10-A1B2C3D4E5F6
# entries <id:name>...: the working exercises.json, with its contributing note.
entries() {
    local pair sep=""
    { printf '{\n  "contributing": ["Never change, reuse or regenerate an existing id."],\n  "exercises": [\n'
      for pair in "$@"; do
          printf '%s    {\n      "id": "%s",\n      "name": "%s",\n      "startLoad": { "lb": 45, "kg": 20 },\n      "aliases": []\n    }' \
              "$sep" "${pair%%:*}" "${pair#*:}"
          sep=$',\n'
      done
      printf '\n  ]\n}\n'; } >"$REPO/$J"
}
# merged <dir>: main holds Bench (A), Row (B) and Press (C) at version 1; HEAD is branch "pr" at version 2.
merged() {
    new_repo "$1"
    g checkout -qb feat && entries "$A:Bench" "$B:Row" "$C:Press" && set_version 1 && history && append_history 1 &&
        commit "catalog v1" && g checkout -q main && g merge -q --ff-only feat && g checkout -qb pr && set_version 2
}
bump() { append_history 2; }

new_repo "$ADV_TMP/ids-intro"
g checkout -qb feat && entries "$A:Bench" "$B:Row" && set_version 3 && history && append_history 3
expect_exit "I01 first introduction over main's placeholder (no ids to protect) passes" 0 "$(run)" "$(out)"
new_repo "$ADV_TMP/ids-intro-absent" absent
g checkout -qb feat && entries "$A:Bench" && set_version 1 && history && append_history 1
expect_exit "I02 first introduction when main has no exercises.json passes" 0 "$(run)" "$(out)"

merged "$ADV_TMP/ids-reroll" && entries "$A:Bench" "$N:Row" "$C:Press" && bump
expect_exit "I03 a re-rolled id fails with the version raised" 1 "$(run)" "$(out)"
check "I03b the message names the entry and both ids" grep -q "Row was $B and is now $N" "$ADV_TMP/out"
merged "$ADV_TMP/ids-deleted" && entries "$A:Bench" "$C:Press" && bump
expect_exit "I04 a deleted entry fails: its id is gone" 1 "$(run)" "$(out)"
merged "$ADV_TMP/ids-swapped" && entries "$B:Bench" "$A:Row" "$C:Press" && bump
expect_exit "I05 two entries swapping ids fail" 1 "$(run)" "$(out)"
check "I05b both entries are named" is "$(grep -c ' was ' "$ADV_TMP/out")" 2
merged "$ADV_TMP/ids-dup" && entries "$A:Bench" "$A:Row" "$C:Press" && bump
expect_exit "I06 an entry that takes another entry's id (a duplicate) fails" 1 "$(run)" "$(out)"
merged "$ADV_TMP/ids-case" && entries "$A:Bench" "$(tr '[:upper:]' '[:lower:]' <<<"$B"):Row" "$C:Press" && bump
expect_exit "I07 an id re-spelt in lower case fails closed" 1 "$(run)" "$(out)"
merged "$ADV_TMP/ids-broken" && printf '{"exercises": [\n' >"$REPO/$J" && bump
expect_exit "I08 an unreadable working exercises.json with the version raised fails closed (exit 2)" 2 "$(run)" "$(out)"
merged "$ADV_TMP/ids-rm" && rm "$REPO/$J" && printf '2 %064d\n' 0 >>"$REPO/$H"
expect_exit "I09 a deleted exercises.json with the version raised never passes" nonzero "$(run)" "$(out)"
merged "$ADV_TMP/ids-kept" && entries "$C:Press" "$N:Squat" "$A:Barbell Bench Press" "$B:Row" && bump
expect_exit "I10 reordering, renaming and adding with every id kept passes (no false alarm)" 0 "$(run)" "$(out)"

# CI: the PR's merge commit against origin/main, from a full fetch and from pr.yml's shallower checkouts.
merged "$ADV_TMP/ids-ci" && entries "$A:Bench" "$N:Row" "$C:Press" && bump && commit "re-roll Row"
ORIGIN="$ADV_TMP/ids-origin.git" && git clone -q --bare "$REPO" "$ORIGIN"
REPO="$ADV_TMP/ids-merge" && git clone -q "$ORIGIN" "$REPO" && g checkout -q --detach origin/main &&
    g merge -q --no-ff --no-edit origin/pr && g push -q origin HEAD:refs/heads/pull-1-merge
expect_exit "I11 CI's detached merge commit with a re-rolled id fails" 1 "$(run)" "$(out)"
REPO="$ADV_TMP/ids-depth2" && git clone -q --depth 2 --no-single-branch --branch pull-1-merge "file://$ORIGIN" "$REPO"
expect_exit "I12 a depth-2 checkout of the merge commit (and origin/main) still finds main and fails the re-roll" 1 "$(run)" "$(out)"
REPO="$ADV_TMP/ids-depth1" && git clone -q --depth 1 --no-single-branch --branch pull-1-merge "file://$ORIGIN" "$REPO"
expect_exit "I13 a depth-1 checkout of the merge commit fails closed (exit 2), never passes" 2 "$(run)" "$(out)"

finish
