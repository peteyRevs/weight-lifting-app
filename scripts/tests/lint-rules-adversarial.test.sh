#!/usr/bin/env bash
# Adversarial fixtures for the design-boundary SwiftLint rules (F06 criterion 8,
# engineering-standards §7/§11): ledger_raw_color, ledger_raw_font, ledger_raw_spacing,
# ledger_raw_radius. Each case is one snippet placed in a feature file (must be flagged by the
# named rule, or by none), and the raw ones again inside LedgerDesign (must pass). The repo's own
# .swiftlint.yml is linted against a throwaway tree that mirrors the repo layout.
#
#   scripts/tests/lint-rules-adversarial.test.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
# Resolve the pinned binary here: mise.toml does not apply inside the throwaway tree.
swiftlint="$(mise which swiftlint)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ledger-lint-adversarial.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp .swiftlint.yml "$work/"
feature="$work/LedgerKit/Sources/FeatureToday"
design="$work/LedgerKit/Sources/LedgerDesign/Components"
app="$work/Apps/Ledger"
tests="$work/LedgerKit/Tests/FeatureTodayTests"
mkdir -p "$feature" "$design" "$app" "$tests"

cases=()  # "<dir>|<id>|<expected rule or none>"

fixture() { # <dir> <id> <expected> <snippet>
    local dir="$1" id="$2" expected="$3" snippet="$4"
    cat > "$dir/$id.swift" <<SWIFT
import SwiftUI

struct Fixture$id: View {
    var body: some View {
        $snippet
    }
}
SWIFT
    cases+=("$dir|$id|$expected")
}

# ---- raw values in a feature must be flagged --------------------------------------------------
# colour
fixture "$feature" C01 ledger_raw_color 'Color(red: 1, green: 0.36, blue: 0.13)'
fixture "$feature" C02 ledger_raw_color 'Color(
            red: 1,
            green: 0.36,
            blue: 0.13
        )'
fixture "$feature" C03 ledger_raw_color 'Color.init(red: 1, green: 0.36, blue: 0.13)'
fixture "$feature" C04 ledger_raw_color 'Color(UIColor.systemOrange)'
fixture "$feature" C05 ledger_raw_color 'Text("x").foregroundStyle(Color(.systemBackground))'
fixture "$feature" C06 ledger_raw_color 'Text("x").foregroundStyle(.purple)'
fixture "$feature" C07 ledger_raw_color 'Text("x").tint(.pink)'
fixture "$feature" C08 ledger_raw_color 'Text("x").shadow(color: .black, radius: 4)'
fixture "$feature" C09 ledger_raw_color 'Rectangle().stroke(.orange)'
fixture "$feature" C10 ledger_raw_color 'Text("x").foregroundStyle(Color("BrandOrange"))'
fixture "$feature" C11 ledger_raw_color 'Text("x").foregroundStyle(Color.orange)'
fixture "$feature" C12 ledger_raw_color 'Color(#colorLiteral(red: 1, green: 0, blue: 0, alpha: 1))'
fixture "$feature" C13 ledger_raw_color 'Color(.sRGB, red: 1, green: 0, blue: 0)'
fixture "$app" C14 ledger_raw_color 'Color(white: 0.5)'
# font
fixture "$feature" F01 ledger_raw_font 'Text("x").font(.system(size: 17))'
fixture "$feature" F02 ledger_raw_font 'Text("x").font(.custom("Helvetica", size: 13))'
fixture "$feature" F03 ledger_raw_font 'Text("x").font(Font.custom("Helvetica", size: 13))'
fixture "$feature" F04 ledger_raw_font 'Text("x").font(.title2.weight(.bold))'
fixture "$feature" F05 ledger_raw_font 'Text("x").bold()'
fixture "$feature" F06 ledger_raw_font 'Text("x").fontWidth(.condensed)'
fixture "$feature" F07 ledger_raw_font 'Text("x").font(Font(UIFont.systemFont(ofSize: 12)))'
fixture "$feature" F08 ledger_raw_font 'Text("x").font(.caption2)'
fixture "$app" F09 ledger_raw_font 'Text("x").fontWeight(.semibold)'
# spacing
fixture "$feature" S01 ledger_raw_spacing 'Text("x").padding(13)'
fixture "$feature" S02 ledger_raw_spacing 'Text("x").padding(.horizontal, 13)'
fixture "$feature" S03 ledger_raw_spacing 'Text("x").padding([.top, .bottom], 13)'
fixture "$feature" S04 ledger_raw_spacing 'Text("x").padding(EdgeInsets(top: 13, leading: 4, bottom: 0, trailing: 0))'
fixture "$feature" S05 ledger_raw_spacing 'VStack(spacing: 13) { Text("x") }'
fixture "$feature" S06 ledger_raw_spacing 'HStack(alignment: .firstTextBaseline, spacing: 13) { Text("x") }'
fixture "$feature" S07 ledger_raw_spacing 'LazyVGrid(columns: [GridItem()], spacing: 13) { Text("x") }'
fixture "$feature" S08 ledger_raw_spacing 'Grid(horizontalSpacing: 13, verticalSpacing: 4) { Text("x") }'
fixture "$feature" S09 ledger_raw_spacing 'Text("x").safeAreaPadding(13)'
fixture "$feature" S10 ledger_raw_spacing 'Text("x").padding(.horizontal, CGFloat(13))'
fixture "$feature" S11 ledger_raw_spacing 'VStack(alignment: .leading,
               spacing: 13) { Text("x") }'
# radius
fixture "$feature" R01 ledger_raw_radius 'RoundedRectangle(cornerRadius: 13)'
fixture "$feature" R02 ledger_raw_radius 'Text("x").clipShape(.rect(cornerRadius: 13))'
fixture "$feature" R03 ledger_raw_radius 'UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)'
fixture "$feature" R04 ledger_raw_radius 'RoundedRectangle(cornerSize: CGSize(width: 13, height: 13))'

# ---- legitimate token use in a feature must not be flagged -------------------------------------
fixture "$feature" N01 none 'Text("x").padding(LedgerSpacing.m)'
fixture "$feature" N02 none 'Text("x").padding(.horizontal, LedgerSpacing.screen)'
fixture "$feature" N03 none 'VStack(spacing: LedgerSpacing.s) { Text("x") }'
fixture "$feature" N04 none 'Text("x").ledgerFont(.body)'
fixture "$feature" N05 none 'Text("x").font(LedgerFont.font(.numeralL))'
fixture "$feature" N06 none 'Text("x").foregroundStyle(LedgerColor.ink).background(LedgerColor.ground).tint(LedgerColor.accent)'
fixture "$feature" N07 none 'RoundedRectangle(cornerRadius: LedgerRadius.card).fill(LedgerColor.accentSoft)'
fixture "$feature" N08 none 'VStack(spacing: 0) { Text("x") }'
fixture "$feature" N09 none 'Text("x") // Features never write .padding(13) or Color(red:); use LedgerDesign tokens.'
fixture "$feature" N10 none 'Text("Tap Color(red: to see the rule")'
fixture "$feature" N11 none 'Text("x").foregroundStyle(highlightColor(red: true))'
fixture "$feature" N12 none 'Text("x").frame(width: 44, height: 44).font(LedgerFont.archivo(size: 30, weight: 700, width: 88))'
fixture "$feature" N13 none 'Text("x").padding(.top, LedgerSpacing.xl).shadow(color: LedgerColor.hairline, radius: LedgerRadius.row)'

# ---- raw values inside LedgerDesign and in tests are allowed -----------------------------------
fixture "$design" D01 none 'Color(red: 1, green: 0.36, blue: 0.13)'
fixture "$design" D02 none 'Text("x").font(.system(size: 17)).padding(13)'
fixture "$design" D03 none 'RoundedRectangle(cornerRadius: 13).fill(Color.orange)'
fixture "$tests" T01 none 'Text("x").font(.system(size: 17)).padding(13).foregroundStyle(Color.red)'

report="$work/report.json"
(cd "$work" && "$swiftlint" lint --quiet --config .swiftlint.yml --reporter json > "$report") || true
python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$report" || { echo "swiftlint produced no report" >&2; exit 1; }

failures=0
for entry in "${cases[@]}"; do
    IFS='|' read -r dir id expected <<< "$entry"
    file="$dir/$id.swift"
    hits="$(python3 - "$report" "$file" <<'PY'
import json, os, sys
report, target = sys.argv[1], os.path.realpath(sys.argv[2])
rules = sorted({v["rule_id"] for v in json.load(open(report))
                if os.path.realpath(v["file"]) == target and v["rule_id"].startswith("ledger_raw_")})
print(" ".join(rules) or "none")
PY
)"
    label="${dir#"$work"/}/$id.swift"
    if [[ "$expected" == none && "$hits" != none ]]; then
        echo "FAIL $label: false positive — flagged by $hits"
        failures=$((failures + 1))
    elif [[ "$expected" != none && " $hits " != *" $expected "* ]]; then
        echo "FAIL $label: raw value not flagged by $expected (hits: $hits)"
        failures=$((failures + 1))
    else
        echo "ok   $label ($hits)"
    fi
done

echo "lint-rules-adversarial: ${#cases[@]} cases, $failures failed"
[[ $failures -eq 0 ]]
