#!/usr/bin/env bash
# Fixture test for the design-system lint rules (F06 acceptance criterion 8).
# The same raw colour / font / spacing / radius code must fail in a feature
# module and in an app shell, and pass inside LedgerDesign, the only module
# allowed to spell raw values.
#
#   scripts/tests/lint-rules.test.sh      (run by check.sh step 2)
set -euo pipefail

cd "$(dirname "$0")/../.."
CONFIG="$PWD/.swiftlint.yml"
SWIFTLINT="$(mise which swiftlint)"   # resolved here: mise.toml does not apply inside $WORK
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# rule name → a line of SwiftUI that breaks it
RULES=(ledger_raw_color ledger_raw_font ledger_raw_spacing ledger_raw_radius)
SNIPPETS=(
    'Text("a").foregroundStyle(Color(red: 1, green: 0.36, blue: 0.13))'
    'Text("a").font(.system(size: 17))'
    'Text("a").padding(13)'
    'Text("a").clipShape(RoundedRectangle(cornerRadius: 12))'
)

fixture() { # <module dir> <snippet>
    mkdir -p "$WORK/$1"
    printf 'import SwiftUI\n\nstruct Fixture: View {\n    var body: some View {\n        %s\n    }\n}\n' "$2" \
        >"$WORK/$1/Fixture.swift"
    echo "$WORK/$1/Fixture.swift"
}

violations() { # <file> → the custom-rule identifiers SwiftLint reports
    (cd "$WORK" && "$SWIFTLINT" lint --strict --quiet --config "$CONFIG" "$1" 2>/dev/null || true) |
        grep -o '(ledger_raw_[a-z]*)' | tr -d '()' || true
}

failures=0
check() { # <description> <condition>
    if eval "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; failures=$((failures + 1)); fi
}

for i in "${!RULES[@]}"; do
    rule="${RULES[$i]}" snippet="${SNIPPETS[$i]}"
    feature="$(violations "$(fixture "LedgerKit/Sources/FeatureToday" "$snippet")")"
    app="$(violations "$(fixture "Apps/Ledger" "$snippet")")"
    design="$(violations "$(fixture "LedgerKit/Sources/LedgerDesign" "$snippet")")"
    check "$rule fails a feature module" '[[ "$feature" == "$rule" ]]'
    check "$rule fails an app shell" '[[ "$app" == "$rule" ]]'
    check "$rule passes inside LedgerDesign" '[[ -z "$design" ]]'
done

if [[ $failures -gt 0 ]]; then
    echo "lint-rules: $failures check(s) failed" >&2
    exit 1
fi
echo "lint-rules: ${#RULES[@]} rules × 3 modules OK"
