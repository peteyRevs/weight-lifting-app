#!/usr/bin/env bash
# Asserts that LedgerKit's target graph still matches the table in
# tasks/features/F00-project-skeleton.md (architecture §3). Adding an edge is an
# ADR decision, so this fails loudly instead of letting the graph drift.
#
#   scripts/check-package-graph.sh            # verify (used by check.sh step 2)
#   scripts/check-package-graph.sh --record   # rewrite the expected file
set -euo pipefail

cd "$(dirname "$0")/.."
EXPECTED="LedgerKit/package-graph.expected.txt"

read -r -d '' NORMALISE <<'PY' || true
import json, sys

package = json.load(sys.stdin)
for target in sorted(package["targets"], key=lambda t: t["name"]):
    edges = sorted(set(target.get("target_dependencies", []) + target.get("product_dependencies", [])))
    print("%s %s: %s" % (target["type"], target["name"], ", ".join(edges) if edges else "-"))
PY

actual() {
    swift package --package-path LedgerKit describe --type json | python3 -c "$NORMALISE"
}

if [[ "${1:-}" == "--record" ]]; then
    actual > "$EXPECTED"
    echo "recorded $(wc -l < "$EXPECTED" | tr -d ' ') targets to $EXPECTED"
    exit 0
fi

if [[ ! -f "$EXPECTED" ]]; then
    echo "error: $EXPECTED is missing; run scripts/check-package-graph.sh --record" >&2
    exit 1
fi

if ! diff -u "$EXPECTED" <(actual); then
    echo >&2
    echo "error: LedgerKit's target graph differs from $EXPECTED." >&2
    echo "       Intended? Update the table in the feature brief / architecture §3," >&2
    echo "       then re-record with scripts/check-package-graph.sh --record." >&2
    exit 1
fi

echo "package graph matches $EXPECTED"
