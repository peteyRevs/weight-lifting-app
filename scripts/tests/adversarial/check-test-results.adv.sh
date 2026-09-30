#!/usr/bin/env bash
# scripts/check-test-results.sh against result bundles that lie: xcrun is faked so
# `xcresulttool get test-results tests` prints a chosen tree (the Xcode 26 shape:
# testNodes[] = test plan, its children = test bundles with nodeType/name/result).
set -uo pipefail
source "$(dirname "$0")/lib.sh"

CHECK="$ROOT/scripts/check-test-results.sh"
T="$ADV_TMP"
mkdir -p "$T/bin"
cat >"$T/bin/xcrun" <<'SH'
#!/bin/sh
# Fake xcrun: `xcresulttool get test-results tests --path <bundle>` prints
# <bundle>/tests.json, or fails like a missing/corrupt bundle when it is absent.
while [ $# -gt 0 ]; do [ "$1" = --path ] && { bundle="$2"; break; }; shift; done
[ -f "$bundle/tests.json" ] || { echo "Error: invalid result bundle" >&2; exit 1; }
cat "$bundle/tests.json"
SH
chmod +x "$T/bin/xcrun"
export PATH="$T/bin:$PATH"

cat >"$T/PR.xctestplan" <<'JSON'
{ "version": 1, "testTargets": [
  { "target": { "containerPath": "container:LedgerKit", "identifier": "LedgerDomainTests", "name": "LedgerDomainTests" } },
  { "target": { "containerPath": "container:LedgerKit", "identifier": "LedgerDesignTests", "name": "LedgerDesignTests" } },
  { "target": { "containerPath": "container:Ledger.xcodeproj", "identifier": "LedgerUITests", "name": "LedgerUITests" },
    "selectedTests": ["Smoke"] },
  { "target": { "containerPath": "container:LedgerKit", "identifier": "LedgerHealthTests", "name": "LedgerHealthTests" },
    "enabled": false }
] }
JSON

# bundle <name> <Bundle:Result>...: a result bundle whose plan node holds these bundles.
bundle() {
    local dir="$T/$1.xcresult"; shift
    mkdir -p "$dir"
    python3 - "$dir/tests.json" "$@" <<'PY'
import json, sys
out, specs = sys.argv[1], sys.argv[2:]
kids = [{"name": n, "nodeType": "UI test bundle" if n.endswith("UITests") else "Unit test bundle",
         "result": r, "children": []} for n, r in (s.split(":") for s in specs)]
json.dump({"devices": [], "testPlanConfigurations": [],
           "testNodes": [{"name": "PR", "nodeType": "Test Plan", "result": "Passed", "children": kids}]},
          open(out, "w"))
PY
}
run() { out="$("$CHECK" "$T/$1.xcresult" "${2:-$T/PR.xctestplan}" 2>&1)"; code=$?; }

bundle ok LedgerDomainTests:Passed LedgerDesignTests:Passed LedgerUITests:Passed
run ok
expect_exit "R01 every enabled plan target ran and passed" 0 "$code" "$out"

bundle failed LedgerDomainTests:Failed LedgerDesignTests:Passed LedgerUITests:Passed
run failed
expect_exit "R02 one bundle failed -> fails" 1 "$code" "$out"

bundle missing LedgerDesignTests:Passed LedgerUITests:Passed
run missing
expect_exit "R03 LedgerDomainTests silently missing -> fails" 1 "$code" "$out"
check "R03b the error names the missing target" grep -q 'did not run: LedgerDomainTests' <<<"$out"

bundle none
run none
expect_exit "R04 no bundles ran -> fails" 1 "$code" "$out"

mkdir -p "$T/corrupt.xcresult"
run corrupt
expect_exit "R05 unreadable bundle -> fails" 1 "$code" "$out"
run does-not-exist
expect_exit "R06 bundle path does not exist -> fails" 1 "$code" "$out"

bundle skipped LedgerDomainTests:Skipped LedgerDesignTests:Passed LedgerUITests:Passed
run skipped
expect_exit "R07 a bundle whose tests were all skipped -> fails" 1 "$code" "$out"

bundle xfail LedgerDomainTests:"Expected Failure" LedgerDesignTests:Passed LedgerUITests:Passed
run xfail
expect_exit "R08 bundle result 'Expected Failure' is not 'Passed' -> fails" 1 "$code" "$out"

mkdir -p "$T/nested.xcresult"
cat >"$T/nested.xcresult/tests.json" <<'JSON'
{ "testNodes": [ { "name": "PR", "nodeType": "Test Plan", "result": "Passed", "children": [
  { "name": "Default", "nodeType": "Test Plan Configuration", "result": "Passed", "children": [
    { "name": "LedgerDomainTests", "nodeType": "Unit test bundle", "result": "Passed" },
    { "name": "LedgerDesignTests", "nodeType": "Unit test bundle", "result": "Passed" },
    { "name": "LedgerUITests", "nodeType": "UI test bundle", "result": "Passed" } ] } ] } ] }
JSON
run nested
expect_exit "R09 an unexpected tree shape (extra level) fails closed" 1 "$code" "$out"

mkdir -p "$T/garbage.xcresult"
echo "not json" >"$T/garbage.xcresult/tests.json"
run garbage
expect_exit "R10 non-JSON test results fail" nonzero "$code" "$out"

mkdir -p "$T/nulltype.xcresult"
echo '{"testNodes":[{"children":[{"name":"LedgerDomainTests","result":"Passed"}]}]}' >"$T/nulltype.xcresult/tests.json"
run nulltype
expect_exit "R11 a child without nodeType fails closed" nonzero "$code" "$out"

run ok "$T/missing.xctestplan"
expect_exit "R12 missing test plan fails" nonzero "$code" "$out"

echo '{"version": 1}' >"$T/empty.xctestplan"
run ok "$T/empty.xctestplan"
expect_exit "R13 a plan with no testTargets fails" nonzero "$code" "$out"

# The committed plans: every target the plan enables must be a real test target,
# so a typo cannot turn into "did not run" noise or, worse, a disabled target.
for plan in PR PR-Watch Nightly Nightly-Watch; do
    file="$ROOT/TestPlans/$plan.xctestplan"
    disabled="$(jq -r '[.testTargets[] | select(.enabled == false) | .target.name] | join(",")' "$file")"
    if [[ -z "$disabled" ]]; then
        pass "R14 $plan.xctestplan disables no test target"
    else
        fail "R14 $plan.xctestplan disables no test target" "disabled: $disabled"
    fi
done

finish
