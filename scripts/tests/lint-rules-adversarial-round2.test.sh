#!/usr/bin/env bash
# Round 2 of the adversarial fixtures for the ledger_raw_* SwiftLint rules, against the regexes
# rewritten in the F06 fix round (7439e3d). Same harness as lint-rules-adversarial.test.sh: one
# fixture file per case in a throwaway tree that mirrors the repo, linted once with the repo's own
# .swiftlint.yml. A case expects one rule, `any` ledger_raw_* rule, or `none`.
#
# Not wired into check.sh while it has open cases (it would stop the gate at step 2); see
# tasks/features/F06-design-system/test-findings.md, "Round 2".
#
#   scripts/tests/lint-rules-adversarial-round2.test.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
# Resolve the pinned binary here: mise.toml does not apply inside the throwaway tree.
swiftlint="$(mise which swiftlint)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ledger-lint-adversarial2.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp .swiftlint.yml "$work/"
feature="$work/LedgerKit/Sources/FeatureToday"
design="$work/LedgerKit/Sources/LedgerDesign/Components"
mkdir -p "$feature" "$design"

cases=()  # "<dir>|<id>|<expected rule, any or none>"

fixture() { # <dir> <id> <expected> <snippet>
    local dir="$1" id="$2" expected="$3" snippet="$4"
    cat > "$dir/$id.swift" <<SWIFT
import SwiftUI

struct Fixture$id: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.legibilityWeight) private var legibilityWeight
    @ScaledMetric private var titleSize: CGFloat = 32
    var isDone = false
    var isCompact = false
    var custom: Color?

    var body: some View {
        $snippet
    }
}
SWIFT
    cases+=("$dir|$id|$expected")
}

# ---- raw values the rewritten regexes still miss: ordinary feature spellings (bugs) -----------
# colour: a named colour after `=`, `?` or `??` instead of `(`, `[`, `,` or `:`
fixture "$feature" B01 ledger_raw_color 'let tint: Color = .orange
        Text("x").foregroundStyle(tint)'
fixture "$feature" B02 ledger_raw_color 'Text("x").foregroundStyle(isDone ? .green : LedgerColor.inkMuted)'
fixture "$feature" B03 ledger_raw_color 'Text("x").foregroundStyle(custom ?? .red)'
fixture "$feature" B04 ledger_raw_color 'let brand: Color = .init(red: 1, green: 0.36, blue: 0.13)
        Text("x").foregroundStyle(brand)'
# font: a system style chosen by a ternary
fixture "$feature" B05 ledger_raw_font 'Text("x").font(isCompact ? .footnote : .body)'
# spacing: EdgeInsets spelled `.init`, the scroll-margin API, and Spacer's minimum length
fixture "$feature" B06 ledger_raw_spacing 'Text("x").padding(.init(top: 13, leading: 0, bottom: 0, trailing: 0))'
fixture "$feature" B07 ledger_raw_spacing 'List { Text("x").listRowInsets(.init(top: 8, leading: 26, bottom: 8, trailing: 26)) }'
fixture "$feature" B08 ledger_raw_spacing 'ScrollView { Text("x") }.contentMargins(.horizontal, 26, for: .scrollContent)'
fixture "$feature" B09 ledger_raw_spacing 'HStack { Text("x"); Spacer(minLength: 13); Text("y") }'
# radius: per-corner radii through RectangleCornerRadii (the iOS 17 spelling of a sheet's top corners)
fixture "$feature" B10 ledger_raw_radius 'Rectangle().clipShape(.rect(cornerRadii: .init(topLeading: 28, topTrailing: 28)))'
fixture "$feature" B11 ledger_raw_radius 'UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 28, topTrailing: 28))'

# ---- the design system's own escape hatches and near-tokens (design questions) ----------------
# LedgerFont's public Font entry points accept a fixed text size from a feature. (Round 1's N12
# keeps `LedgerFont.archivo(size:weight:width:)` legal: the brief makes it public.)
fixture "$feature" D01 ledger_raw_font 'Text("x").font(LedgerFont.font(.numeralL, dynamicTypeSize: .large))'
fixture "$feature" D02 ledger_raw_font 'Text("x").font(LedgerFont.font(.label, size: 13))'
fixture "$feature" D04 any 'Text("x").ledgerFont(.body).dynamicTypeSize(.large)'
# A raw alpha on an ink token: a colour off the AA ladder and outside Increase Contrast.
fixture "$feature" D05 ledger_raw_color 'Text("x").foregroundStyle(LedgerColor.ink.opacity(0.6))'
# Token arithmetic with a literal.
fixture "$feature" D06 ledger_raw_spacing 'Text("x").padding(.horizontal, LedgerSpacing.m + 1)'
# Letter-spacing and leading are type properties the roles own.
fixture "$feature" D07 any 'Text("x").ledgerFont(.body).tracking(2)'
fixture "$feature" D08 any 'Text("x").ledgerFont(.body).lineSpacing(4)'
fixture "$feature" D09 ledger_raw_font 'Text("x").font(.init(CTFontCreateWithName("Helvetica" as CFString, 13, nil)))'

# ---- must not be flagged: the sanctioned API, tokens, zero, and non-code ----------------------
fixture "$feature" P01 none 'Text("x").font(LedgerFont.font(.body, dynamicTypeSize: dynamicTypeSize))'
fixture "$feature" P02 none 'Text("x").font(LedgerFont.font(.title, size: titleSize, legibilityWeight: legibilityWeight))'
fixture "$feature" P03 none 'Text("x").font(LedgerFont.font(.caption, dynamicTypeSize: dynamicTypeSize))'
fixture "$feature" P13 none 'Text("x").ledgerFont(.title).ledgerFont(.caption)'
fixture "$feature" P04 none 'RoundedRectangle(cornerSize: CGSize(width: LedgerRadius.row, height: LedgerRadius.row))'
fixture "$feature" P05 none 'Text("x").padding(EdgeInsets(top: 0, leading: LedgerSpacing.screen, bottom: 0, trailing: LedgerSpacing.screen))'
fixture "$feature" P06 none 'Text("x").padding(.top, -LedgerSpacing.s).padding(.horizontal, 0)'
fixture "$feature" P07 none 'HStack(spacing: .zero) { Text("x") }.clipShape(.rect(cornerRadius: 0))'
fixture "$feature" P08 none 'let note = """
            Use .padding(13) and Color(red: 1, green: 0, blue: 0) only inside LedgerDesign.
            """
        Text(note)'
fixture "$feature" P09 none 'Text(#"Color(red: 1) .font(.system(size: 9)) cornerRadius: 12"#)'
fixture "$feature" P10 none 'Text("x") /* .padding(13), Color.red, .font(.body) */'
fixture "$feature" P11 none 'Label("Swap", systemImage: "arrow.left.arrow.right").labelStyle(.titleAndIcon)'
fixture "$feature" P12 none 'LazyVGrid(columns: [GridItem(.flexible(minimum: 40), spacing: LedgerSpacing.s)]) { Text("x") }'

# ---- controls: still flagged after the rewrite ------------------------------------------------
fixture "$feature" K01 ledger_raw_spacing 'Text("x").padding(
            .horizontal,
            13
        )'
fixture "$feature" K02 ledger_raw_color 'Text("x").shadow(color: .black.opacity(0.3), radius: 8)'
fixture "$feature" K03 ledger_raw_spacing 'LazyVGrid(columns: [GridItem(.fixed(80), spacing: 13)]) { Text("x") }'
fixture "$feature" K04 ledger_raw_spacing 'Text("x").padding(EdgeInsets(top: 0, leading: LedgerSpacing.m, bottom: 0, trailing: 13))'
fixture "$feature" K05 ledger_raw_radius 'Rectangle().clipShape(.rect(topLeadingRadius: 28, topTrailingRadius: 28))'
fixture "$feature" K06 ledger_raw_font 'Text("x").font(.title3.weight(.bold))'
# LedgerDesign may spell every raw value above.
fixture "$design" K07 none 'Text("x").font(isCompact ? .footnote : .body).padding(.init(top: 13, leading: 0, bottom: 0, trailing: 0))'

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
    elif [[ "$expected" == any && "$hits" == none ]]; then
        echo "FAIL $label: raw value not flagged by any ledger_raw_* rule"
        failures=$((failures + 1))
    elif [[ "$expected" != none && "$expected" != any && " $hits " != *" $expected "* ]]; then
        echo "FAIL $label: raw value not flagged by $expected (hits: $hits)"
        failures=$((failures + 1))
    else
        echo "ok   $label ($hits)"
    fi
done

echo "lint-rules-adversarial-round2: ${#cases[@]} cases, $failures failed"
[[ $failures -eq 0 ]]
