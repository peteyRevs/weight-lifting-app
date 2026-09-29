#!/usr/bin/env bash
# Fixture test for the design-system lint rules (F06 acceptance criterion 8).
# The same raw colour / font / spacing / radius code must fail in a feature
# module and in an app shell, and pass inside LedgerDesign, the only module
# allowed to spell raw values. The rules cover only the modules that can draw
# UI: Foundation-only code is not flagged (F06 review S2).
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

# Scope (F06 review S2, engineering-standards §7): Foundation-only code that spells a plate colour and
# a name-length rule. Every module that can draw UI flags it; the Foundation-only modules do not.
UI_MODULES=(LedgerKit/Sources/FeatureToday LedgerKit/Sources/WatchFeatureWorkout LedgerKit/Sources/LedgerAppKit
    LedgerKit/Sources/LedgerWatchAppKit Apps/Ledger Apps/LedgerWatch)
FOUNDATION_MODULES=(LedgerDomain LedgerDependencies LedgerPersistence LedgerHealth LedgerSync LedgerActivityKit)
foundation_fixture() { # <module dir>
    mkdir -p "$WORK/$1"
    printf '%s\n' 'import Foundation' '' 'enum PlateColor { case black, red }' '' \
        'struct NameRule { let minLength: Int }' '' 'let nameRule = NameRule(minLength: 2)' '' \
        'func plateColor(kilograms: Int) -> PlateColor {' '    if kilograms >= 25 { return .red }' \
        '    return .black' '}' >"$WORK/$1/Plate.swift"
    echo "$WORK/$1/Plate.swift"
}
for module in "${UI_MODULES[@]}"; do
    found="$(violations "$(foundation_fixture "$module")" | sort -u | tr '\n' ' ')"
    check "colour and spacing rules reach ${module#LedgerKit/Sources/}" \
        '[[ "$found" == "ledger_raw_color ledger_raw_spacing " ]]'
done
for module in "${FOUNDATION_MODULES[@]}"; do
    found="$(violations "$(foundation_fixture "LedgerKit/Sources/$module")")"
    check "Foundation-only $module is not flagged (return .black, minLength: 2)" '[[ -z "$found" ]]'
done

# Known limit (standards §7, F06 review N8): fails once a rule flags it, so §7's list stays true.
spec="$(violations "$(fixture "LedgerKit/Sources/FeatureToday" \
    'Text("a").font(LedgerFont.font(.body, size: LedgerFont.Role.body.spec.size))')")"
check "known limit, not flagged: a role's spec size as a fixed size (else update standards §7)" '[[ -z "$spec" ]]'

if [[ $failures -gt 0 ]]; then
    echo "lint-rules: $failures check(s) failed" >&2
    exit 1
fi
echo "lint-rules: ${#RULES[@]} rules × 3 modules OK; scope: ${#UI_MODULES[@]} UI modules flagged," \
    "${#FOUNDATION_MODULES[@]} Foundation-only modules not flagged"
