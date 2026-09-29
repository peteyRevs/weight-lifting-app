#!/usr/bin/env bash
# Round 3 of the adversarial fixtures for the ledger_raw_* SwiftLint rules, against the regexes
# rewritten in F06 fix round 2 (7689a74): the `=`/`?`/`??` colour branch, `.init(red:…)`, a raw
# alpha on a token, the tracking/leading/size/text-size font branches, content margins, Spacer
# and token arithmetic. Same harness as rounds 1 and 2: one fixture file per case in a throwaway
# tree that mirrors the repo, linted once with the repo's own .swiftlint.yml. A case expects one
# rule, `any` ledger_raw_* rule, `none`, or `limit`.
#
# F06 fix round 3 — Pete's decision 2 (2026-09-29): "The design lint is a tripwire, not a proof."
# The rule set is frozen; "tokens only" is enforced by review (docs/subagent-workflow.md, review
# point 4). Cases the decision puts out of scope are kept below as `limit`: a documented known
# limit (docs/engineering-standards.md §7) that the rules do not flag. A `limit` case fails only if
# a rule starts flagging it, so the documented list stays true. Wired into check.sh step 2 since
# fix round 3; see tasks/features/F06-design-system/test-findings.md, "Round 3".
#
#   scripts/tests/lint-rules-adversarial-round3.test.sh
set -euo pipefail

cd "$(dirname "$0")/../.."
# Resolve the pinned binary here: mise.toml does not apply inside the throwaway tree.
swiftlint="$(mise which swiftlint)"
work="$(mktemp -d "${TMPDIR:-/tmp}/ledger-lint-adversarial3.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp .swiftlint.yml "$work/"
feature="$work/LedgerKit/Sources/FeatureToday"
design="$work/LedgerKit/Sources/LedgerDesign/Components"
mkdir -p "$feature" "$design"

cases=()  # "<dir>|<id>|<expected rule, any or none>"

fixture() { # <dir> <id> <expected> <snippet>: the snippet is a view body
    local dir="$1" id="$2" expected="$3" snippet="$4"
    cat > "$dir/$id.swift" <<SWIFT
import SwiftUI

struct Fixture$id: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var isDone = false
    var isCompact = false
    var isSheet = false

    var body: some View {
        $snippet
    }
}
SWIFT
    cases+=("$dir|$id|$expected")
}

file_fixture() { # <dir> <id> <expected> <contents>: the whole file after `import SwiftUI`
    local dir="$1" id="$2" expected="$3" contents="$4"
    printf 'import SwiftUI\n\n%s\n' "$contents" > "$dir/$id.swift"
    cases+=("$dir|$id|$expected")
}

# ---- raw values the fix-round-2 regexes still miss: ordinary feature spellings (bugs) ---------
# colour: a named colour after `{` or `return` (implicit and explicit returns)
file_fixture "$feature" B01 ledger_raw_color 'struct FixtureB01: View {
    var accent: Color { .orange }
    var body: some View { Text("x").foregroundStyle(accent) }
}'
file_fixture "$feature" B02 ledger_raw_color 'struct FixtureB02: View {
    var isDone = false
    var body: some View { Text("x").foregroundStyle(tint) }
    private var tint: Color {
        if isDone {
            return .green
        }
        return LedgerColor.ink
    }
}'
# colour: the fifth hierarchical level (the rule lists primary…quaternary)
fixture "$feature" B03 ledger_raw_color 'Text("x").foregroundStyle(.quinary)'
# colour: a raw alpha on a token through ShapeStyle hierarchy instead of .opacity(…)
fixture "$feature" B04 ledger_raw_color 'Text("x").foregroundStyle(LedgerColor.accent.secondary)'
# colour: a raw alpha on a token, the chain wrapped by the formatter
fixture "$feature" B05 ledger_raw_color 'Text("x").foregroundStyle(
            LedgerColor.ink
                .opacity(0.6)
        )'
# colour: Color.Resolved is a ShapeStyle (iOS 17)
fixture "$feature" B06 ledger_raw_color 'Text("x").foregroundStyle(Color.Resolved(red: 1, green: 0.36, blue: 0.13))'
# colour: GraphicsContext shading in a Canvas (a chart in a feature)
fixture "$feature" B07 ledger_raw_color 'Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(red: 1, green: 0.36, blue: 0.13))
        }'
# font: a system style assigned to a Font, then used
fixture "$feature" B08 ledger_raw_font 'let titleFont: Font = .title
        Text("x").font(titleFont)'
# font: the environment key instead of the modifier
fixture "$feature" B09 ledger_raw_font 'Text("x").environment(\.font, .system(size: 13))'
# font: the size and design siblings of .fontWeight/.fontWidth/.fontDesign. `.textScale(.secondary)`
# is only caught by accident: ledger_raw_color reads `(.secondary` as a colour (B10 is a control).
# (Fix round 3: ledger_raw_font now flags `.textScale(` and `.monospaced(` as role properties.)
fixture "$feature" B10 any 'Text("x").ledgerFont(.body).textScale(.secondary)'
fixture "$feature" B11 ledger_raw_font 'Text("x").ledgerFont(.numeralL).monospaced()'
# spacing and radius: a literal chosen by a ternary
fixture "$feature" B12 ledger_raw_spacing 'Text("x").padding(.horizontal, isCompact ? 13 : LedgerSpacing.l)'
fixture "$feature" B13 ledger_raw_spacing 'HStack(spacing: isCompact ? 4 : LedgerSpacing.s) { Text("x") }'
fixture "$feature" B14 ledger_raw_radius 'RoundedRectangle(cornerRadius: isSheet ? 28 : LedgerRadius.card)'
# radius: the iOS 26 corner API (.rect(corners:), ConcentricRectangle)
fixture "$feature" B15 ledger_raw_radius 'Rectangle().clipShape(.rect(corners: .concentric(minimum: .fixed(13))))'
# a trailing comment inside the call: the match spans a comment token and SwiftLint drops it.
# Known limit (decision 2): SwiftLint drops any match that contains a comment, and no simple rule
# can skip the comment; the same call with the comment after it is flagged (K02, K04).
fixture "$feature" B16 limit 'Text("x").font(
            isCompact // tight rows
                ? .footnote
                : .body
        )'
fixture "$feature" B17 limit 'Text("x").padding(
            .horizontal, // screen inset
            13
        )'

# ---- escape hatches around the roles and tokens (design questions) ---------------------------
# Known limits (decision 2): finding 22's escape hatches are documented in
# docs/engineering-standards.md §7, not closed; review catches them. Each was `any` in round 3.
# A cap on the text size: `.dynamicTypeSize(.large)` is flagged, `...large` is not.
fixture "$feature" D01 limit 'Text("x").ledgerFont(.body).dynamicTypeSize(...DynamicTypeSize.large)'
# Shrinks a watch role below the 11 pt floor (criterion 4).
fixture "$feature" D02 limit 'Text("x").ledgerFont(.watchLabel).minimumScaleFactor(0.5)'
# The same raw alpha as LedgerColor.ink.opacity(0.6), applied to the view.
fixture "$feature" D03 limit 'Text("x").foregroundStyle(LedgerColor.ink).opacity(0.6)'
# A gap made with a frame, and a gap in a named constant.
fixture "$feature" D04 limit 'VStack(spacing: 0) { Text("x"); Spacer().frame(height: 13); Text("y") }'
file_fixture "$feature" D05 limit 'struct FixtureD05: View {
    private let rowGap: CGFloat = 13
    var body: some View { Text("x").padding(.vertical, rowGap) }
}'
# System styles that are colours by another name.
fixture "$feature" D06 limit 'Rectangle().fill(.separator).frame(height: LedgerHairline.width)'
fixture "$feature" D07 limit 'Text("x").background(.ultraThinMaterial)'
# Role properties outside the role.
fixture "$feature" D08 limit 'Text("x").ledgerFont(.caption).baselineOffset(2)'
fixture "$feature" D09 limit 'Text("x").ledgerFont(.body).textCase(.uppercase)'

# ---- must not be flagged: sanctioned token use ----------------------------------------------
fixture "$feature" P01 none 'Text("x").font(LedgerFont.font(.label, size: LedgerFont.scaledSize(.label, dynamicTypeSize: dynamicTypeSize)))'
fixture "$feature" P02 none 'Text("x").lineLimit(2).ledgerFont(.body).environment(\.dynamicTypeSize, dynamicTypeSize)'
fixture "$feature" P03 none 'VStack(spacing: 0) { Spacer(minLength: 0) }
            .background(Color.clear)
            .overlay(LinearGradient(colors: [LedgerColor.ground, .clear], startPoint: .top, endPoint: .bottom))'
fixture "$feature" P04 none 'Group {
            if dynamicTypeSize >= .accessibility1 || dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: LedgerSpacing.s) { Text("x") }
            } else {
                HStack(spacing: LedgerSpacing.s) { Text("x") }
            }
        }'
fixture "$feature" P05 none 'RoundedRectangle(cornerRadius: LedgerRadius.card - LedgerSpacing.s).fill(LedgerColor.surface)'
fixture "$feature" P06 none 'Text("x").padding(.bottom, LedgerSpacing.xl + LedgerSpacing.s).padding(.top, -LedgerSpacing.xs)'
fixture "$feature" P07 none 'Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())'
fixture "$feature" P08 none 'NavigationStack { Text("x").toolbar { ToolbarItem(placement: .primaryAction) { Text("y") } } }'
fixture "$feature" P09 none 'ProgressView(value: 0.5).tint(LedgerColor.accent).foregroundStyle(LedgerColor.accentText)'
fixture "$feature" P10 none 'Text("x").ledgerFont(isDone ? .caption : .body).foregroundStyle(isDone ? LedgerColor.inkMuted : LedgerColor.ink)'

# ---- must not be flagged, but are: false positives on sanctioned use (design questions) ------
# A feature preview at an accessibility size (standards §7: a #Preview per meaningful state).
file_fixture "$feature" Q01 none '#Preview("AX3") {
    Text("x").ledgerFont(.body).dynamicTypeSize(.accessibility3)
}'
# The content width inside the screen insets.
fixture "$feature" Q02 none 'GeometryReader { proxy in
            Text("x").frame(width: proxy.size.width - 2 * LedgerSpacing.screen)
        }'
# A feature enum whose cases share a colour name, assigned with `=`.
file_fixture "$feature" Q03 none 'enum Emphasis { case primary, secondary }

struct FixtureQ03: View {
    private let emphasis: Emphasis = .primary
    var body: some View { Text("x") }
}'

# ---- controls: still flagged ------------------------------------------------------------------
fixture "$feature" K01 ledger_raw_color 'let tint: Color = isDone ? .green : LedgerColor.ink
        Text("x").foregroundStyle(tint)'
fixture "$feature" K02 ledger_raw_spacing 'Text("x").padding(.horizontal, 13) // screen inset'
fixture "$feature" K03 ledger_raw_font 'Text("x").font(LedgerFont.font(.body, dynamicTypeSize: min(dynamicTypeSize, .accessibility2)))'
fixture "$feature" K04 ledger_raw_font 'Text("x").font(isCompact ? .footnote : .body) // tight rows'
# LedgerDesign may spell every raw value above.
fixture "$design" K05 none 'Text("x").font(
            isCompact // tight rows
                ? .footnote
                : .body
        )
        .padding(.horizontal, isCompact ? 13 : LedgerSpacing.l)
        .foregroundStyle(LedgerColor.accent.secondary)
        .clipShape(.rect(corners: .concentric(minimum: .fixed(13))))'

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
    if [[ "$expected" == limit ]]; then
        if [[ "$hits" != none ]]; then
            echo "FAIL $label: documented limit is now flagged by $hits; update docs/engineering-standards.md §7"
            failures=$((failures + 1))
        else
            echo "limit $label (known limit, decision 2)"
        fi
    elif [[ "$expected" == none && "$hits" != none ]]; then
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

echo "lint-rules-adversarial-round3: ${#cases[@]} cases, $failures failed"
[[ $failures -eq 0 ]]
