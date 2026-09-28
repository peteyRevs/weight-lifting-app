#!/usr/bin/env bash
# scripts/coverage-gate.sh against hostile xccov reports and threshold files.
# Reports are built here in the shape `xcrun xccov view --report --json` prints
# (targets[].files[] with an absolute path, coveredLines, executableLines).
set -uo pipefail
source "$(dirname "$0")/lib.sh"

GATE="${ADV_COVERAGE_GATE:-$ROOT/scripts/coverage-gate.sh}" # override: mutation-test this suite
SRC="$ROOT/LedgerKit/Sources"
T="$ADV_TMP"

# report <out.json> <target|path|covered/executable>...
# A path without a leading "/" is relative to this checkout's LedgerKit/Sources.
report() {
    python3 - "$SRC" "$@" <<'PY'
import json, sys
src, out, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
targets = {}
for spec in specs:
    target, path, lines = spec.split("|")
    covered, executable = map(int, lines.split("/"))
    path = path if path.startswith("/") else f"{src}/{path}"
    targets.setdefault(target, []).append({
        "name": path.rsplit("/", 1)[1], "path": path,
        "coveredLines": covered, "executableLines": executable,
        "lineCoverage": covered / executable if executable else 0, "functions": []})
def total(files, key): return sum(f[key] for f in files)
json.dump({
    "coveredLines": 0, "executableLines": 0, "lineCoverage": 0,
    "targets": [{"name": name, "buildProductPath": f"/dd/{name}",
                 "coveredLines": total(files, "coveredLines"),
                 "executableLines": total(files, "executableLines"),
                 "lineCoverage": 0, "files": files} for name, files in targets.items()],
}, open(out, "w"), indent=1)
PY
}

cat >"$T/thresholds.json" <<'JSON'
{
  "overall": 80,
  "modules": { "LedgerDomain": 95, "LedgerDesign": 60, "WatchFeatureWorkout": 70, "Feature*": 70 },
  "required": ["LedgerDomain"],
  "excludedModules": ["LedgerTestSupport"],
  "excludedFiles": ["*+Previews.swift", "*/Generated/*"]
}
JSON
export LEDGER_COVERAGE_THRESHOLDS="$T/thresholds.json"
unset GITHUB_STEP_SUMMARY

# gate <inputs...>: runs the gate, sets $code and $out (stdout+stderr).
gate() {
    out="$("$GATE" "$@" 2>&1)"
    code=$?
}

# ---- thresholds: boundaries ------------------------------------------------
report "$T/exact.json" "D.xctest|LedgerDomain/A.swift|95/100"
gate "$T/exact.json"
expect_exit "C01 threshold exactly met (95.00 vs 95) passes" 0 "$code" "$out"

report "$T/below.json" "D.xctest|LedgerDomain/A.swift|9499/10000"
gate "$T/below.json"
expect_exit "C02 0.01 below the threshold (94.99 vs 95) fails" 1 "$code" "$out"

report "$T/floor.json" "D.xctest|LedgerDomain/A.swift|18999/20000"
gate "$T/floor.json"
expect_exit "C03 94.995 % is floored, never rounded up to 95, and fails" 1 "$code" "$out"

sed 's/"LedgerDomain": 95/"LedgerDomain": 95.5/' "$T/thresholds.json" >"$T/decimal.json"
report "$T/d955.json" "D.xctest|LedgerDomain/A.swift|955/1000"
report "$T/d954.json" "D.xctest|LedgerDomain/A.swift|954/1000"
LEDGER_COVERAGE_THRESHOLDS="$T/decimal.json" gate "$T/d955.json"
expect_exit "C04a decimal threshold 95.5 met exactly passes" 0 "$code" "$out"
LEDGER_COVERAGE_THRESHOLDS="$T/decimal.json" gate "$T/d954.json"
expect_exit "C04b decimal threshold 95.5 missed by 0.1 fails" 1 "$code" "$out"

report "$T/overall.json" "D.xctest|LedgerDesign/A.swift|60/100" "D.xctest|FeatureToday/A.swift|70/100"
gate "$T/overall.json"
expect_exit "C05 every module passes but overall (65 %) misses 80 -> fails" 1 "$code" "$out"

# ---- attribution -------------------------------------------------------------
report "$T/prefix.json" "D.xctest|LedgerDomain/A.swift|100/100" "D.xctest|LedgerDomainExtras/B.swift|0/100"
gate "$T/prefix.json"
expect_exit "C06a LedgerDomainExtras (no threshold) fails the gate" 1 "$code" "$out"
check "C06b LedgerDomainExtras is not merged into LedgerDomain" \
    grep -q '| LedgerDomain | 100 / 100 |' <<<"$out"
check "C06c the error names LedgerDomainExtras" grep -q 'LedgerDomainExtras has no threshold' <<<"$out"

report "$T/outside.json" \
    "D.xctest|LedgerDomain/A.swift|100/100" \
    "Ledger.app|$ROOT/Apps/Ledger/LedgerApp.swift|0/1000" \
    "D.xctest|$ROOT/LedgerKit/Tests/LedgerDomainTests/ATests.swift|0/1000" \
    "D.xctest|$ROOT/.derivedData/SourcePackages/checkouts/swift-snapshot-testing/Sources/SnapshotTesting/A.swift|0/1000" \
    "D.xctest|/elsewhere/NotLedgerKit/Sources/LedgerDomain/A.swift|0/1000" \
    "D.xctest|$ROOT/LedgerKit/Sources/Loose.swift|0/1000"
gate "$T/outside.json"
expect_exit "C07 files outside LedgerKit/Sources/<Module>/ never count" 0 "$code" "$out"

report "$T/excluded.json" \
    "D.xctest|LedgerDomain/A.swift|100/100" \
    "D.xctest|LedgerDomain/A+Previews.swift|0/1000" \
    "D.xctest|LedgerDomain/Generated/Strings.swift|0/1000" \
    "D.xctest|LedgerTestSupport/Fakes.swift|0/1000"
gate "$T/excluded.json"
expect_exit "C08 excluded files and modules never count" 0 "$code" "$out"

report "$T/f69.json" "F.xctest|FeatureToday/A.swift|69/100" "D.xctest|LedgerDomain/A.swift|1000/1000"
report "$T/f70.json" "F.xctest|FeatureToday/A.swift|70/100" "D.xctest|LedgerDomain/A.swift|1000/1000"
gate "$T/f69.json"
expect_exit "C09a Feature* wildcard applies: FeatureToday 69 % fails" 1 "$code" "$out"
# (FeatureToday has code here, so it must be "required" too; F3 fix)
sed 's/"required": \["LedgerDomain"\]/"required": ["LedgerDomain", "FeatureToday"]/' "$T/thresholds.json" >"$T/feature.json"
LEDGER_COVERAGE_THRESHOLDS="$T/feature.json" gate "$T/f70.json"
expect_exit "C09b Feature* wildcard applies: FeatureToday 70 % passes" 0 "$code" "$out"

# A package file is linked into several binaries of one run; its best binary counts.
report "$T/multi.json" "LedgerDomainTests.xctest|LedgerDomain/A.swift|96/100" "Ledger.app|LedgerDomain/A.swift|5/100"
gate "$T/multi.json"
expect_exit "C10 same file in two binaries of one run: best measurement wins" 0 "$code" "$out"

report "$T/placeholder.json" "D.xctest|LedgerDomain/A.swift|100/100" "D.xctest|LedgerSync/LedgerSync.swift|0/0"
gate "$T/placeholder.json"
expect_exit "C11 a module whose files have no executable lines is not failed" 0 "$code" "$out"

# ---- iOS and watchOS bundles disagree -----------------------------------------
# The same file compiles to different code per platform when it has #if os(...)
# branches, so the two reports can disagree on executableLines for one file.
report "$T/ios-half.json" "D.xctest|LedgerDomain/A.swift|50/100"
report "$T/watch-small.json" "D.xctest|LedgerDomain/A.swift|10/10"
gate "$T/ios-half.json" "$T/watch-small.json"
expect_exit "C12 [F2] iOS 50/100 + watchOS 10/10 for one file must not pass as 100 %" 1 "$code" "$out"

report "$T/ios-zero.json" "D.xctest|LedgerDomain/A.swift|0/100" "D.xctest|LedgerDomain/B.swift|1000/1000"
report "$T/watch-empty.json" "D.xctest|LedgerDomain/A.swift|0/0"
gate "$T/ios-zero.json"
ios_alone=$code
gate "$T/ios-zero.json" "$T/watch-empty.json"
if [[ $ios_alone -eq 1 && $code -eq 1 ]]; then
    pass "C13 [F2] adding a bundle where the file has 0 lines cannot hide its 100 uncovered lines"
else
    fail "C13 [F2] adding a bundle where the file has 0 lines cannot hide its 100 uncovered lines" \
        "iOS alone exits $ios_alone; iOS + watchOS exits $code
$out"
fi

# ---- thresholded module missing from the report --------------------------------
# LedgerDomain has sources in this checkout; a report without it means it was not
# measured (coverage targets narrowed, bundle dropped), not that it has no code.
[[ -n "$(find "$SRC/LedgerDomain" -name '*.swift' -print -quit)" ]] || fail "C14 precondition: LedgerDomain has sources"
report "$T/no-domain.json" "D.xctest|LedgerDesign/A.swift|100/100"
gate "$T/no-domain.json"
expect_exit "C14 [F3] LedgerDomain has sources and a threshold but is absent from the report -> fails" 1 "$code" "$out"
check "C14b the error names the missing LedgerDomain" grep -q 'LedgerDomain: no lines measured' <<<"$out"

# ---- the step summary (criterion 4) ------------------------------------------
report "$T/d94.json" "D.xctest|LedgerDomain/A.swift|94/100"
: >"$T/summary.md"
out="$(GITHUB_STEP_SUMMARY="$T/summary.md" "$GATE" "$T/d94.json" 2>&1)"; code=$?
expect_exit "C15a Domain at 94 % fails" 1 "$code" "$out"
check "C15b \$GITHUB_STEP_SUMMARY gets the table with the ✗ row" \
    grep -qF '| LedgerDomain | 94 / 100 | 94.00 % | 95 % | ✗ |' "$T/summary.md"

# ---- bad inputs ----------------------------------------------------------------
gate "$T/does-not-exist.json"
expect_exit "C16 missing report -> exit 2" 2 "$code" "$out"
gate
expect_exit "C17 no arguments -> exit 2" 2 "$code" "$out"
: >"$T/empty.json"
gate "$T/empty.json"
expect_exit "C18 empty report file fails" nonzero "$code" "$out"
head -c 120 "$T/exact.json" >"$T/truncated.json"
gate "$T/truncated.json"
expect_exit "C19 truncated report fails" nonzero "$code" "$out"
echo '{}' >"$T/nothing.json"
gate "$T/nothing.json"
expect_exit "C20 report with no targets fails (nothing measured)" 1 "$code" "$out"
echo '{"targets": null}' >"$T/null.json"
gate "$T/null.json"
expect_exit "C21 report with targets: null fails" nonzero "$code" "$out"
gate "$T/exact.json" "$T/does-not-exist.json"
expect_exit "C22 one good and one missing report -> exit 2" 2 "$code" "$out"

# ---- .xcresult inputs, with xcrun faked ------------------------------------------
mkdir -p "$T/bin" "$T/bundle.xcresult"
cat >"$T/bin/xcrun" <<'SH'
#!/bin/sh
# Fake xcrun for `xccov view --report --json <bundle>`: $FAKE_XCCOV picks the behaviour.
case "$FAKE_XCCOV" in
    fail) echo "Error: Failed to locate coverage data" >&2; exit 1 ;;
    silent) exit 0 ;;
    garbage) echo "not json"; exit 0 ;;
    *) cat "$FAKE_XCCOV" ;;
esac
SH
chmod +x "$T/bin/xcrun"
PATH="$T/bin:$PATH" FAKE_XCCOV=fail gate "$T/bundle.xcresult"
expect_exit "C23 bundle without coverage data -> exit 2" 2 "$code" "$out"
PATH="$T/bin:$PATH" FAKE_XCCOV=silent gate "$T/bundle.xcresult"
expect_exit "C24 xccov prints nothing -> fails" nonzero "$code" "$out"
PATH="$T/bin:$PATH" FAKE_XCCOV=garbage gate "$T/bundle.xcresult"
expect_exit "C25 xccov prints non-JSON -> fails" nonzero "$code" "$out"
PATH="$T/bin:$PATH" FAKE_XCCOV="$T/d94.json" gate "$T/bundle.xcresult"
expect_exit "C26 bundle path goes through xccov and is gated (94 % fails)" 1 "$code" "$out"
if xcrun --find xccov >/dev/null 2>&1; then
    mkdir -p "$T/empty.xcresult"
    gate "$T/empty.xcresult"
    expect_exit "C27 real xccov on an empty .xcresult directory -> exit 2" 2 "$code" "$out"
else
    skip "C27 real xccov on an empty .xcresult directory" "no xccov"
fi

# ---- malformed thresholds -------------------------------------------------------
bad_thresholds() { # <name> <json> <expected>
    printf '%s' "$2" >"$T/bad-thresholds.json"
    LEDGER_COVERAGE_THRESHOLDS="$T/bad-thresholds.json" gate "$T/exact.json"
    expect_exit "$1" "$3" "$code" "$out"
}
bad_thresholds "C28 thresholds file is not JSON -> fails" '{"overall": 80,' nonzero
bad_thresholds "C29 thresholds without \"overall\" -> fails" \
    '{"modules": {"LedgerDomain": 95}, "excludedModules": [], "excludedFiles": []}' nonzero
bad_thresholds "C30 threshold given as a string -> fails" \
    '{"overall": 80, "modules": {"LedgerDomain": "95"}, "excludedModules": [], "excludedFiles": []}' nonzero
bad_thresholds "C31 threshold null -> treated as missing, fails" \
    '{"overall": 80, "modules": {"LedgerDomain": null}, "excludedModules": [], "excludedFiles": []}' 1
LEDGER_COVERAGE_THRESHOLDS="$T/missing-thresholds.json" gate "$T/exact.json"
expect_exit "C32 thresholds file missing -> fails" nonzero "$code" "$out"
bad_thresholds "C33 [F5] unparseable thresholds is bad input: exit 2 per the script's contract" \
    '{"overall": 80,' 2

# ---- the committed thresholds match docs/testing-strategy.md §4 -------------------
python3 - "$ROOT/scripts/coverage-thresholds.json" >"$T/committed.txt" 2>&1 <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
want = {"LedgerDomain": 95, "LedgerPersistence": 90, "LedgerSync": 90, "LedgerHealth": 80,
        "LedgerActivityKit": 70, "WatchFeatureWorkout": 70, "Feature*": 70, "LedgerDesign": 60}
bad = [f"{k}: {c['modules'].get(k)} != {v}" for k, v in want.items() if c["modules"].get(k) != v]
if c["overall"] != 80: bad.append(f"overall {c['overall']} != 80")
print("\n".join(bad)); sys.exit(1 if bad else 0)
PY
code=$?
expect_exit "C34 committed thresholds equal testing-strategy §4" 0 "$code" "$(cat "$T/committed.txt")"

finish
