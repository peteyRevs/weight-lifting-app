#!/usr/bin/env bash
# The coverage gate (docs/testing-strategy.md §4): line coverage per LedgerKit
# module against scripts/coverage-thresholds.json.
#
# Coverage is plan-wide and package targets are never coverage targets of their
# own (F00 implementation notes #17), so a module is its source folder,
# LedgerKit/Sources/<Module>/, not a target in the report. App shells and tests
# never count. A file measured twice (two test bundles, iOS and watchOS) keeps
# its best measurement. A module with lines but no threshold fails, so that
# every new module gets one on purpose.
#
#   scripts/coverage-gate.sh <result.xcresult | xccov-report.json>...
#
# Prints a Markdown table, also appended to $GITHUB_STEP_SUMMARY when set.
# Exit 0: all thresholds met. 1: a threshold missed or missing. 2: bad input.
set -euo pipefail

cd "$(dirname "$0")/.."
THRESHOLDS="${LEDGER_COVERAGE_THRESHOLDS:-scripts/coverage-thresholds.json}"

[[ $# -gt 0 ]] || { echo "usage: scripts/coverage-gate.sh <result.xcresult | report.json>..." >&2; exit 2; }
for input in "$@"; do
    [[ -e "$input" ]] || { echo "error: $input does not exist" >&2; exit 2; }
done

read -r -d '' GATE <<'PY' || true
import fnmatch, json, math, os, re, subprocess, sys

thresholds_file, inputs = sys.argv[1], sys.argv[2:]
config = json.load(open(thresholds_file))
source = re.compile(r"/LedgerKit/Sources/(([^/]+)/.+)$")

def report(path):
    if path.endswith(".json"):
        return json.load(open(path))
    run = subprocess.run(["xcrun", "xccov", "view", "--report", "--json", path], capture_output=True, text=True)
    if run.returncode:
        print(f"error: no coverage report in {path}: {run.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return json.loads(run.stdout)

def score(lines):
    return (lines[0] / lines[1] if lines[1] else 1.0, lines[1])

best = {}  # "<Module>/<path>" -> (covered, executable)
for path in inputs:
    for target in report(path).get("targets", []):
        for file in target.get("files", []):
            match = source.search(file["path"])
            if not match or match.group(2) in config["excludedModules"] \
                    or any(fnmatch.fnmatch(match.group(1), p) for p in config["excludedFiles"]):
                continue
            name, lines = match.group(1), (file["coveredLines"], file["executableLines"])
            if name not in best or score(lines) > score(best[name]):
                best[name] = lines

modules = {}
for name, (covered, executable) in best.items():
    total = modules.setdefault(name.split("/", 1)[0], [0, 0])
    total[0], total[1] = total[0] + covered, total[1] + executable
modules = {m: t for m, t in sorted(modules.items()) if t[1]}

def threshold(module):
    limits = config["modules"]
    return limits.get(module, next((v for p, v in limits.items() if fnmatch.fnmatchcase(module, p)), None))

rows, failures = ["### Coverage gate", "", "| Module | Lines | Coverage | Threshold | |", "|---|--:|--:|--:|:-:|"], []
def row(label, covered, executable, limit):
    percent = math.floor(10000 * covered / executable) / 100 if executable else 0.0  # never rounds up
    if limit is None:
        failures.append(f"{label} has no threshold; add it to {thresholds_file}")
    elif not executable:
        failures.append(f"{label}: no LedgerKit source lines measured (is code coverage on in the test plan?)")
    elif percent < limit:
        failures.append(f"{label} is at {percent:.2f} %, below its {limit} % threshold")
    ok = limit is not None and percent >= limit and executable
    rows.append(f"| {label} | {covered} / {executable} | {percent:.2f} % | {'none' if limit is None else f'{limit} %'} | {'✓' if ok else '✗'} |")

for module, (covered, executable) in modules.items():
    row(module, covered, executable, threshold(module))
row("Overall", sum(t[0] for t in modules.values()), sum(t[1] for t in modules.values()), config["overall"])
unmeasured = [m for m in config["modules"] if "*" not in m and m not in modules]
if unmeasured:
    rows += ["", f"No executable lines measured yet: {', '.join(unmeasured)}."]

table = "\n".join(rows) + "\n"
print(table, flush=True)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(table)
for failure in failures:
    print(f"error: coverage gate: {failure}", file=sys.stderr)
sys.exit(1 if failures else 0)
PY

python3 -c "$GATE" "$THRESHOLDS" "$@"
