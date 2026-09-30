#!/usr/bin/env bash
# The coverage gate (docs/testing-strategy.md §4): line coverage per LedgerKit/Sources/<Module>/
# (coverage is plan-wide, F00 notes #17) against scripts/coverage-thresholds.json. A file measured
# twice (two bundles, iOS and watchOS) keeps the measurement with the most lines, then most covered.
# "required" lists every module with code: one missing from the report fails (its test target was
# dropped), and a measured one fails until it is listed.
#
#   scripts/coverage-gate.sh [--ios-only] <result.xcresult | xccov-report.json>...
#
# --ios-only (check.sh --ios-only, PR CI): the inputs hold no watchOS bundle, so a required module listed
# in "watchOnly" (only a watchOS bundle can measure it) is not failed for being missing; a note names it.
# Every other module is gated as usual, and without the flag "watchOnly" changes nothing.
#
# Prints a Markdown table (also to $GITHUB_STEP_SUMMARY). Exit 0: all thresholds met; 1: a
# threshold missed or missing; 2: bad input.
set -euo pipefail

cd "$(dirname "$0")/.."
THRESHOLDS="${LEDGER_COVERAGE_THRESHOLDS:-scripts/coverage-thresholds.json}"
IOS_ONLY=0
if [[ "${1:-}" == --ios-only ]]; then IOS_ONLY=1; shift; fi

[[ $# -gt 0 ]] || { echo "usage: scripts/coverage-gate.sh [--ios-only] <result.xcresult | report.json>..." >&2; exit 2; }
for input in "$@"; do
    [[ -e "$input" ]] || { echo "error: $input does not exist" >&2; exit 2; }
done

read -r -d '' GATE <<'PY' || true
import fnmatch, json, math, os, re, subprocess, sys

thresholds_file, ios_only, inputs = sys.argv[1], sys.argv[2] == "1", sys.argv[3:]
source = re.compile(r"/LedgerKit/Sources/(([^/]+)/.+)$")

def bad_input(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(2)

def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)

try:
    config = json.load(open(thresholds_file))
    limits, excluded, excluded_files = config["modules"], config["excludedModules"], config["excludedFiles"]
    required, watch_only = config.get("required", []), config.get("watchOnly", [])
    lists = (excluded, excluded_files, required, watch_only)
    if not all(isinstance(names, list) and all(isinstance(n, str) for n in names) for names in lists):
        raise ValueError("excludedModules, excludedFiles, required and watchOnly must be lists of names")
    if any(m not in required for m in watch_only):
        raise ValueError('every "watchOnly" module must be "required" too')
    if not is_number(config["overall"]) or not all(v is None or is_number(v) for v in limits.values()):
        raise ValueError("thresholds must be numbers")
    if any(m in required or any(fnmatch.fnmatchcase(m, p) for p in limits) for m in excluded):
        raise ValueError("a module cannot be both gated (by name or pattern) and excluded")
except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
    bad_input(f"{thresholds_file} is not a usable thresholds file: {error}")

def report(path):
    if path.endswith(".json"):
        text = open(path).read()
    else:
        run = subprocess.run(["xcrun", "xccov", "view", "--report", "--json", path], capture_output=True, text=True)
        if run.returncode:
            bad_input(f"no coverage report in {path}: {run.stderr.strip()}")
        text = run.stdout
    try:
        return [(f["path"], f["coveredLines"], f["executableLines"])
                for t in json.loads(text).get("targets") or [] for f in t.get("files", [])]
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        bad_input(f"{path} is not an xccov report: {error}")

best = {}  # "<Module>/<path>" -> (executable, covered): the largest measurement wins
for path in inputs:
    for file_path, covered, executable in report(path):
        match = source.search(file_path)
        if not match or match.group(2) in excluded \
                or any(fnmatch.fnmatch(match.group(1), p) for p in excluded_files):
            continue
        best[match.group(1)] = max(best.get(match.group(1), (0, 0)), (executable, covered))

modules = {}
for name, (executable, covered) in best.items():
    total = modules.setdefault(name.split("/", 1)[0], [0, 0])
    total[0], total[1] = total[0] + covered, total[1] + executable
modules = {m: t for m, t in sorted(modules.items()) if t[1]}

def threshold(module):
    return limits.get(module, next((v for p, v in limits.items() if fnmatch.fnmatchcase(module, p)), None))

title = "### Coverage gate (iOS only)" if ios_only else "### Coverage gate"
rows, failures = [title, "", "| Module | Lines | Coverage | Threshold | |", "|---|--:|--:|--:|:-:|"], []
def row(label, covered, executable, limit):
    percent = math.floor(10000 * covered / executable) / 100 if executable else 0.0  # never rounds up
    if limit is None:
        failures.append(f"{label} has no threshold; add it to {thresholds_file}")
    elif not executable:
        failures.append(f"{label}: no lines measured (is code coverage on, and did its test target run?)")
    elif percent < limit:
        failures.append(f"{label} is at {percent:.2f} %, below its {limit} % threshold")
    ok = limit is not None and percent >= limit and executable
    rows.append(f"| {label} | {covered} / {executable} | {percent:.2f} % | {'none' if limit is None else f'{limit} %'} | {'✓' if ok else '✗'} |")

skipped = [m for m in watch_only if ios_only and m not in modules]  # one the inputs measured is gated as usual
for module in sorted((set(modules) | set(required)) - set(skipped)):
    covered, executable = modules.get(module, (0, 0))
    row(module, covered, executable, threshold(module))
    if module in modules and module not in required:
        failures.append(f'{module} has coverage now; add it to "required" in {thresholds_file}')
row("Overall", sum(t[0] for t in modules.values()), sum(t[1] for t in modules.values()), config["overall"])
unmeasured = [m for m in limits if "*" not in m and m not in modules and m not in required]
if unmeasured:
    rows += ["", f"No executable lines measured yet: {', '.join(unmeasured)}."]
if skipped:
    rows += ["", f"Not gated in an iOS-only run (only watchOS measures them): {', '.join(skipped)}."]

table = "\n".join(rows) + "\n"
print(table, flush=True)
if os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        summary.write(table)
for failure in failures:
    print(f"error: coverage gate: {failure}", file=sys.stderr)
sys.exit(1 if failures else 0)
PY

python3 -c "$GATE" "$THRESHOLDS" "$IOS_ONLY" "$@"
