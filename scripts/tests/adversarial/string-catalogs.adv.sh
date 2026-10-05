#!/usr/bin/env bash
# scripts/check-string-catalogs.sh (F09): a module's String Catalog must hold exactly the keys the
# module's code looks up, written as xcstringstool writes them. Nothing here is hand-made build output:
# the small Swift sources below are compiled once by the real compiler, which writes one .stringsdata
# per source, and every case runs the real script, and so the real xcstringstool, on a throwaway
# repository holding some of those sources, their .stringsdata where check.sh's iOS build leaves them,
# and a catalog. So the cases also pin how the compiler keys a lookup. The script runs under /bin/bash
# (3.2 on macOS), whatever bash runs this suite. No simulator, no network.
# needs macOS: the fixtures are compiled by xcrun swiftc, and the script runs xcrun xcstringstool.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

SCRIPT="${ADV_CHECK_STRING_CATALOGS:-$ROOT/scripts/check-string-catalogs.sh}" # override: mutation-test this suite
SRC="$ADV_TMP/sources"
DATA="$ADV_TMP/stringsdata"
BUILD=".derivedData/Build/Intermediates.noindex/LedgerKit.build" # in a repository; iOS is Debug-iphonesimulator
mkdir -p "$SRC" "$DATA" "$ADV_TMP/objects"

# ---- the fixture sources -------------------------------------------------------------------------
# lookup <file> <parameters> <string literal>: a source whose one lookup is that literal.
lookup() {
    printf 'import Foundation\nprivate func text(%s) -> String { String(localized: %s, bundle: .module) }\n' \
        "$2" "$3" >"$SRC/$1.swift"
}
echo 'import Foundation
extension Foundation.Bundle { static let module = Bundle.main } // SwiftPM writes this accessor in a package' >"$SRC/Stub.swift"
cat >"$SRC/TabsCopy.swift" <<'SWIFT'
import Foundation
enum TabsCopy {
    static var today: String { String(localized: "Today", bundle: .module) }
    static var history: String { String(localized: "History", bundle: .module) }
}
SWIFT
cat >"$SRC/SoundCopy.swift" <<'SWIFT'
import Foundation
enum SoundCopy {
    static var today: String { String(localized: "Today", bundle: .module, comment: "Tab title") }
    static var history: String { String(localized: "History", bundle: .module) }
    static var done: String { String(localized: "100% done", bundle: .module) }
    static func sets(count: Int) -> String { String(localized: "\(count) sets", bundle: .module) }
}
SWIFT
cat >"$SRC/StartView.swift" <<'SWIFT'
import SwiftUI
struct StartView: View {
    var body: some View { Text("Start workout") }
}
SWIFT
cat >"$SRC/OnlyAComment.swift" <<'SWIFT'
import Foundation
// String(localized: "Start workout", bundle: .module)
enum OnlyAComment {}
SWIFT
echo 'enum NoLookup {}' >"$SRC/NoLookup.swift"
# Lookups that are not in a copy file (re-review R1), and two files whose names only come near one.
cat >"$SRC/Tabs+Previews.swift" <<'SWIFT'
#if DEBUG
    import SwiftUI
    struct TabsPreviewContent: View {
        var body: some View { Text("Sample row") }
    }
#endif
SWIFT
cat >"$SRC/RatioView.swift" <<'SWIFT'
import SwiftUI
struct RatioView: View {
    let done: Int
    let total: Int
    var body: some View { Button("\(done)/\(total)") {} }
}
SWIFT
cat >"$SRC/TabsCopy+More.swift" <<'SWIFT'
import Foundation
extension TabsCopy { static var settings: String { String(localized: "Settings", bundle: .module) } }
SWIFT
cat >"$SRC/CopyButton.swift" <<'SWIFT'
import Foundation
enum CopyButton { static var copy: String { String(localized: "Copy", bundle: .module) } }
SWIFT
cat >"$SRC/StaticTotalCopy.swift" <<'SWIFT'
import Foundation
private enum Block {
    static let total = 8
    static var length: String { String(localized: "\(total) weeks", bundle: .module) }
}
SWIFT
lookup StartCopy '' '"Start workout"'
lookup PercentPlainCopy '' '"100% done"'
lookup PercentValueCopy 'week: Int' '"\(week)% of the block"'
lookup SetsIntCopy 'count: Int' '"\(count) sets"'
lookup SetsStringCopy 'count: String' '"\(count) sets"'
lookup CafeCopy '' "$(printf '"Caf\xc3\xa9 stop"')" # composed: U+00E9
# moved from CatalogBuildAdversarialTests.auditKey_isFoundationsKey (100% done and N% of the block are above)
lookup Key01Copy 'week: Int, total: Int' '"Week \(week) of \(total)"'
lookup Key02Copy 'name: String, tag: String' '"Next: \(name) · \(tag)"'
lookup Key03Copy 'week: Int, total: Int, name: String' '"\(week) of \(total) sets · \(name) lb moved"'
lookup Key06Copy 'name: String' '"Can'"'"'t open \"\(name)\""'
lookup Key07Copy '' '"Rest\tday"'
lookup Key08Copy '' '"Line one\nLine two"'
lookup Key09Copy 'name: String' '"Up next \u{2014} \(name)"'
lookup Key10Copy 'name: String' '#"Back\slash \#(name)"#'
lookup Key11Copy 'name: String' '"\(name)"'
lookup Key12Copy 'week: Int, total: Int, name: String' '"\(week) × \(total) @ \(name)"'
# moved from CopyFileAdversarialTests.interpolationNotABareParameter_isAFinding (StaticTotalCopy is above)
lookup WeekPlusOneCopy 'week: Int' '"Week \(week + 1)"'
lookup MovedDoubleCopy 'value: Double' '"\(value) lb moved"'
lookup SetsInt64Copy 'count: Int64' '"\(count) sets"'
lookup SetsSubstringCopy 'count: Substring' '"\(count) sets"'
lookup SetsOptionalCopy 'count: Int?' '"\(count) sets"'
lookup WeekSomeIntegerCopy 'week: some BinaryInteger' '"Week \(week)"'
lookup SetsFormattedCopy 'count: Int' '"\(count, format: .number) sets"'
lookup SetsUppercasedCopy 'count: String' '"\(count.uppercased()) sets"'
lookup NestedLookupCopy '' '"\(String(localized: "Start workout", bundle: .module)) now"'
cat >"$SRC/OtherMembersParameterCopy.swift" <<'SWIFT'
import Foundation
private enum Weeks {
    static func week(_ week: Int) -> String { String(localized: "Week \(week)", bundle: .module) }
    static var weeks: String { String(localized: "\(week) weeks", bundle: .module) }
}
SWIFT

# One compile for every fixture, for the host, as a Debug build (the preview's source is inside #if DEBUG):
# each source's keys land in $DATA/<Source>.stringsdata.
# -wmo compiles them in one process, a fraction of a second; file by file, as Xcode's Debug build does,
# the compiler writes the same files (compared on 2026-10-04) in several seconds.
if ! compiler_says="$(cd "$ADV_TMP/objects" && xcrun swiftc -c -wmo -D DEBUG -module-name Fixtures \
    -emit-localized-strings -emit-localized-strings-path "$DATA" "$SRC"/*.swift 2>&1)"; then
    fail "SC00 the fixture sources compile, and the compiler writes their .stringsdata" "$compiler_says"
    finish
    exit 1
fi
check "SC00 the fixture sources compile, and the compiler writes one .stringsdata per source" \
    is "$(find "$DATA" -name '*.stringsdata' | grep -c .)" "$(find "$SRC" -name '*.swift' | grep -c .)"

# ---- fixture repositories ------------------------------------------------------------------------
# module <repository> <Module> <Source>...: adds a module to the repository $ADV_TMP/<repository>: those
# sources, and their .stringsdata where the iOS build leaves them. Sets $R and $CATALOG for the next calls.
module() {
    local source objects
    R="$ADV_TMP/$1"
    CATALOG="LedgerKit/Sources/$2/Resources/Localizable.xcstrings"
    objects="$R/$BUILD/Debug-iphonesimulator/$2-t.build/Objects-normal/arm64"
    mkdir -p "$R/LedgerKit/Sources/$2/Resources" "$objects"
    shift 2
    for source in "$@"; do
        cp "$SRC/$source.swift" "$R/$(dirname "$(dirname "$CATALOG")")/"
        cp "$DATA/$source.stringsdata" "$objects/"
    done
}
# entry <key> [<comment>]: a catalog entry as xcstringstool writes it, its English text the key itself.
# Both arguments are JSON text: \" \\ \t \n are written as in the file.
entry() {
    printf '    "%s" : {\n' "$1"
    [[ -z "${2:-}" ]] || printf '      "comment" : "%s",\n' "$2"
    printf '      "localizations" : {\n        "en" : {\n          "stringUnit" : {\n            "state" : "translated",\n'
    printf '            "value" : "%s"\n          }\n        }\n      }\n    }' "$1"
}
# counted <key> <one> <other>: an entry whose English text varies by plural, as xcstringstool writes it.
counted() {
    printf '    "%s" : {\n      "localizations" : {\n        "en" : {\n          "variations" : {\n            "plural" : {\n' "$1"
    printf '              "one" : {\n                "stringUnit" : {\n                  "state" : "translated",\n'
    printf '                  "value" : "%s"\n                }\n              },\n' "$2"
    printf '              "other" : {\n                "stringUnit" : {\n                  "state" : "translated",\n'
    printf '                  "value" : "%s"\n                }\n              }\n' "$3"
    printf '            }\n          }\n        }\n      }\n    }'
}
# catalog <entry>...: the current module's catalog, those entries in that order, in the tool's layout
# and ending in a newline, as a hand-written catalog does.
catalog() {
    local separator="" each
    {
        printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n'
        for each in "$@"; do
            printf '%s%s' "$separator" "$each"
            separator=$',\n'
        done
        printf '\n  },\n  "version" : "1.0"\n}\n'
    } >"$R/$CATALOG"
}
# keys <key>...: a catalog of plain entries for those keys, in that order.
keys() {
    local entries=() key
    for key in "$@"; do entries+=("$(entry "$key")"); done
    catalog ${entries[@]+"${entries[@]}"}
}
# run [<derived data>]: the script on the repository $R, from another directory; sets $code and $out.
run() {
    out="$(cd "$ADV_TMP" && /bin/bash "$SCRIPT" "$R" "$@" 2>&1)"
    code=$?
}
# found: "<exit code> <lookups the catalog lacks>/<catalog keys no code looks up>/<diffs against the tool>"
found() {
    printf '%s %s/%s/%s' "$code" "$(grep -c '^  the code looks up ' <<<"$out")" \
        "$(grep -c '^  the catalog has the key ' <<<"$out")" "$(grep -c '^--- LedgerKit/' <<<"$out")"
}
# lacked <key as shown>, unused <key as shown>: how many lines name that key, on that side.
lacked() { grep -cF "  the code looks up $1 (" <<<"$out"; }
unused() { grep -cxF "  the catalog has the key $1, which no code looks up" <<<"$out"; }
# expect <name> <got> <want>: as `check ... is`, and the script's output is shown on a mismatch.
expect() {
    if [[ "$2" == "$3" ]]; then pass "$1"; else
        fail "$1" "got:  $2
want: $3
$out"
    fi
}
passes() { run; expect "$1" "$(found) $(grep -c "^string catalog matches the code: $CATALOG (keys: [0-9]*)$" <<<"$out")" "0 0/0/0 1"; }
# fails_both_ways <name> <the code's key, as shown> <the catalog's key, as shown>
fails_both_ways() { run; expect "$1" "$(found) $(lacked "$2") $(unused "$3")" "1 1/1/0 1 1"; }

# ---- proof cases ---------------------------------------------------------------------------------
module missing Tabs TabsCopy StartCopy && keys 'History' 'Today' && run
expect "SC01 a key the code looks up and the catalog lacks fails, naming the key and where it is looked up" \
    "$(found) $(grep -cxF '  the code looks up "Start workout" (StartCopy.swift:2), which is not a key of the catalog' <<<"$out") \
$(grep -c "^error: $CATALOG and Tabs's code disagree on the keys:$" <<<"$out")" "1 1/0/0 1 1"
check "SC75 ... and the hint offers the two specifiers a key may hold, %lld and %@, and no other (re-review n7)" \
    is "$(grep -c '%lld for an Int, %@ for a String;' <<<"$out") $(grep -cE '%(lf|d|f|s|i)[^a-z]' <<<"$out")" "1 0"

module unused Tabs TabsCopy && keys 'History' 'Settings' 'Today' && run
expect "SC02 a catalog key no code looks up fails, naming the key" "$(found) $(unused '"Settings"')" "1 0/1/0 1"

# xcstringstool sync alone would pass these two: it never marks a "manual" key stale, and a key the
# catalog already calls stale is, to the tool, written as it should be.
marked() { # <key> <extraction state>: the key's entry, saying that of itself
    printf '    "%s" : {\n      "extractionState" : "%s",\n' "$1" "$2"
    entry "$1" | sed 1d
}
module marked Tabs TabsCopy && catalog "$(entry 'History')" "$(marked 'Settings' stale)" "$(entry 'Today')" && run
stale="$(found) $(unused '"Settings"')"
catalog "$(entry 'History')" "$(marked 'Settings' manual)" "$(entry 'Today')" && run
expect "SC68 ... whatever the catalog says of the key: marked \"extractionState\" stale, or manual, it fails the same" \
    "$stale|$(found) $(unused '"Settings"')|$(grep -c '^      "extractionState" : "manual",$' "$R/$CATALOG")" "1 0/1/0 1|1 0/1/0 1|1"

module percent Percent PercentPlainCopy && keys '100% done'
passes "SC03 a plain key with a percent sign: \"100% done\" is keyed 100% done"
keys '100%% done'
fails_both_ways "SC04 ... and a catalog keyed 100%% done fails both ways" '"100% done"' '"100%% done"'

module percent-value Percent PercentValueCopy && keys '%lld%% of the block'
passes "SC05 a key with a value and a percent sign: \"\\(week)% of the block\" is keyed %lld%% of the block"
keys '%lld% of the block'
fails_both_ways "SC06 ... and a catalog keyed %lld% of the block fails both ways" '"%lld%% of the block"' '"%lld% of the block"'

module counted Sets SetsIntCopy && catalog "$(counted '%lld sets' '%lld set' '%lld sets')"
passes "SC07 a counted key (plural one/other) looked up with an Int passes"
module counted-string Sets SetsStringCopy && catalog "$(counted '%lld sets' '%lld set' '%lld sets')"
fails_both_ways "SC08 ... and fails when the code's value is a String (%@ sets)" '"%@ sets"' '"%lld sets"'

# A lookup that is not in a copy file fails by itself (re-review R1): the module's lookups are all in
# <Name>Copy.swift or <Name>Copy+<Area>.swift, and the author is not told to give the catalog a key.
# outside <line as the step prints it>: how many lines say exactly that.
outside() { grep -cxF "  $1" <<<"$out"; }
module bare-text Today TabsCopy StartView && keys 'History' 'Today' && run
expect "SC09 a bare Text(\"Start workout\") in a view file fails as a lookup outside the copy files, with the view's line: \
it is not called a key the catalog lacks, and nothing says to add it" \
    "$(found) $(outside 'StartView.swift:3 looks up "Start workout"') $(grep -c '^error: Today looks up copy outside its copy files:$' <<<"$out") \
$(grep -c 'Give the catalog a key' <<<"$out")" "1 0/0/0 1 1 0"
module preview-keyed Tabs TabsCopy Tabs+Previews && keys 'History' 'Sample row' 'Today' && run
expect "SC77 a preview's Text(\"Sample row\"), inside #if DEBUG, whose key is in the catalog fails the same: the message says Text(verbatim:) for Debug-only code" \
    "$(found) $(outside 'Tabs+Previews.swift:4 looks up "Sample row"') $(grep -c 'write Text(verbatim: "...")' <<<"$out") \
$(grep -c 'hand the view a String' <<<"$out")" "1 0/0/0 1 1 1"
module ratio-keyed Tabs TabsCopy RatioView && keys '%lld/%lld' 'History' 'Today' && run
expect "SC78 a Button(\"\\(done)/\\(total)\"), which has no letter, whose key %lld/%lld is in the catalog fails the same" \
    "$(found) $(outside 'RatioView.swift:5 looks up "%lld/%lld"') $(grep -c 'Do not give the catalog a key for such a lookup' <<<"$out")" "1 0/0/0 1 1"
module copy-area Tabs TabsCopy TabsCopy+More && keys 'History' 'Settings' 'Today'
passes "SC79 a lookup in <Name>Copy+<Area>.swift (TabsCopy+More.swift) is in a copy file: it passes"
module copy-named Tabs TabsCopy CopyButton && keys 'Copy' 'History' 'Today' && run
expect "SC80 a file whose name only starts with Copy (CopyButton.swift) is no copy file: its lookup fails, key in the catalog or not" \
    "$(found) $(outside 'CopyButton.swift:2 looks up "Copy"')" "1 0/0/0 1"
module both-kinds Tabs TabsCopy StartCopy RatioView && keys '%lld/%lld' 'History' 'Settings' 'Today' && run
expect "SC81 a lookup outside the copy files and keys that disagree are both reported, each under its own heading" \
    "$(found) $(outside 'RatioView.swift:5 looks up "%lld/%lld"') $(lacked '"Start workout"') $(unused '"Settings"') \
$(grep -c '^error: Tabs looks up copy outside its copy files:$' <<<"$out") $(grep -c "^error: $CATALOG and Tabs's code disagree on the keys:$" <<<"$out")" \
    "1 1/1/0 1 1 1 1 1"

module twice Tabs TabsCopy && keys 'History' 'Today' 'Today' && run
expect "SC10 a key written twice in the catalog fails: the tool writes it once, and the diff shows it" \
    "$(found) $(grep -c '^-    "Today" : {$' <<<"$out")" "1 0/0/1 1"

module order Tabs TabsCopy && keys 'Today' 'History' && run
expect "SC11 keys out of order (Today before History) fail with the diff (moved from StringCatalogAdversarialTests.keysOutOfOrder_areAProblem)" \
    "$(found) $(grep -c "^error: $CATALOG has the keys the code looks up, but is not written as$" <<<"$out")" "1 0/0/1 1"
keys 'History' 'Today'
passes "SC12 ... and the same keys in order pass"

module spelling Cafe CafeCopy && keys "$(printf 'Cafe\xcc\x81 stop')" # decomposed: e + U+0301
fails_both_ways "SC13 a composed key in code (U+00E9) and a decomposed one in the catalog (e + U+0301) fail both ways, each spelled out \
(moved from CopyFileAdversarialTests.composedAndDecomposedKeys_areNotTheSameKey)" \
    "$(printf '"Caf\xc3\xa9 stop" (spelled "Caf\\u{E9} stop")')" "$(printf '"Cafe\xcc\x81 stop" (spelled "Cafe\\u{301} stop")')"
keys "$(printf 'Caf\xc3\xa9 stop')"
passes "SC14 ... and the composed key in both passes"

sound() { # <Today's comment in the catalog>
    module "sound-$1" Sound SoundCopy NoLookup
    catalog "$(counted '%lld sets' '%lld set' '%lld sets')" "$(entry '100% done')" \
        "$(entry 'History' 'A comment only the catalog gives')" "$(entry 'Today' "$2")"
}
sound same 'Tab title'
passes "SC15 a sound module passes: four keys, one counted, the catalog's comment the one the code gives (comment:)"
sound other 'Title of the tab' && run
expect "SC16 ... and fails when the catalog's comment differs from the code's: the diff shows both" \
    "$(found) $(grep -cx -e '-      "comment" : "Title of the tab",' -e '+      "comment" : "Tab title",' <<<"$out")" "1 0/0/1 2"

module unbuilt Tabs TabsCopy && keys 'History' 'Today' && rm -rf "$R/.derivedData" && run
expect "SC17 a catalog with no .stringsdata (iOS not built) fails with a clear message, rather than pass on nothing" \
    "$(found) $(grep -c "^error: $CATALOG has nothing to be compared with: the iOS build left no$" <<<"$out") \
$(grep -c 'iOS has not been built: scripts/check.sh builds it, then runs this step' <<<"$out")" "1 0/0/0 1 1"
module watch-only Tabs TabsCopy && keys 'History' 'Today' &&
    mv "$R/$BUILD/Debug-iphonesimulator" "$R/$BUILD/Debug-watchsimulator" && run
expect "SC18 ... and the watch build's .stringsdata are not read: the same failure, which says a watch module's catalog waits for F18" \
    "$(found) $(grep -c 'has nothing to be compared with' <<<"$out") \
$(grep -c 'Or Tabs is a watch module, which the iOS build does not compile' <<<"$out") \
$(grep -c 'LedgerWatchAppKit and WatchFeatureWorkout get their catalogs with F18' <<<"$out")" "1 0/0/0 1 1 1"
module stale Tabs TabsCopy && keys 'History' 'Today' &&
    cp "$DATA/StartCopy.stringsdata" "$R/$BUILD/Debug-iphonesimulator/Tabs-t.build/Objects-normal/arm64/"
passes "SC19 a stale .stringsdata, of a source file the module no longer has, is ignored"
module added Tabs TabsCopy StartCopy && keys 'History' 'Start workout' 'Today' &&
    rm "$R/$BUILD/Debug-iphonesimulator/Tabs-t.build/Objects-normal/arm64/StartCopy.stringsdata" && run
expect "SC20 a source file with no .stringsdata (added since the build) fails, naming the file and saying to build again" \
    "$(found) $(grep -cx '         LedgerKit/Sources/Tabs/StartCopy.swift' <<<"$out") $(grep -c 'Build iOS again' <<<"$out")" "1 0/0/0 1 1"

# The script only reads: every file of the repository, the catalog and the build output too, is the same after.
state() { (cd "$R" && find . -type f -exec shasum {} + | LC_ALL=C sort); }
untouched() { # <name> <want from found>
    local before
    before="$(state)"
    run
    expect "$1" "$(found) $([[ "$(state)" == "$before" ]] && echo untouched) $(grep -c Localizable <<<"$before")" "$2 untouched 1"
}
module readonly-pass Tabs TabsCopy && keys 'History' 'Today'
untouched "SC21 the script does not modify the catalog it checks, or any other file: a passing run" "0 0/0/0"
module readonly-keys Tabs TabsCopy && keys 'History' 'Settings' 'Today'
untouched "SC22 ... a run that fails on the keys" "1 0/1/0"
module readonly-layout Tabs TabsCopy && keys 'Today' 'History'
untouched "SC23 ... a run that fails on what the tool would write" "1 0/0/1"
# The tester's ST23-ST25 run the step on a repository without write permission (F9-S1-12). One more shape of
# it: a read-only catalog that ends without a newline, whose copy needs one added before it is compared.
module readonly-no-newline Tabs TabsCopy && keys 'History' 'Today' && text="$(cat "$R/$CATALOG")" &&
    printf '%s' "$text" >"$R/$CATALOG" && chmod a-w "$R/$CATALOG" && run
chmod u+w "$R/$CATALOG"
expect "SC76 a catalog that cannot be written, and ends without a newline, passes: the copy that gets the newline is a new file" \
    "$(found) $(grep -c 'Permission denied' <<<"$out")" "0 0/0/0 0"

# ---- the rest of the script's contract -----------------------------------------------------------
module several Tabs TabsCopy && keys 'History' 'Today'
module several Start StartCopy && keys 'Start workout'
module several Percent PercentPlainCopy && keys '100%% done' && run
expect "SC24 every module's catalog is found and checked: one line each, one failing fails the run, and the count says so" \
    "$(found) $(grep -cx -e 'string catalog matches the code: LedgerKit/Sources/Start/Resources/Localizable.xcstrings (keys: 1)' \
        -e 'string catalog matches the code: LedgerKit/Sources/Tabs/Resources/Localizable.xcstrings (keys: 2)' <<<"$out") \
$(tail -1 <<<"$out")" "1 1/1/0 2 error: string catalogs: 1 of 3 failed this check (above)."
keys '100% done' && run
expect "SC25 ... and once all three match, exit 0 with the count" "$(found) $(tail -1 <<<"$out")" \
    "0 0/0/0 string catalogs: 3 checked, each matches its module's code"

R="$ADV_TMP/no-catalog" && mkdir -p "$R/LedgerKit/Sources/Tabs" && cp "$SRC/TabsCopy.swift" "$R/LedgerKit/Sources/Tabs/" && run
expect "SC26 a repository with no catalog at all fails: the app has copy, so nothing was checked" \
    "$code $(grep -c '^error: no String Catalog at LedgerKit/Sources/<Module>/Resources/Localizable.xcstrings' <<<"$out")" "1 1"

# A module has one catalog, in one place (re-review n4): any other .xcstrings under the sources fails.
# elsewhere <case> <name> <path of the other catalog, in the repository>
elsewhere() {
    module "elsewhere-$1" Tabs TabsCopy && keys 'History' 'Today' && mkdir -p "$R/$(dirname "$3")" && cp "$R/$CATALOG" "$R/$3" && run
    expect "$1 $2" "$(found) $(grep -c "^string catalog matches the code: $CATALOG (keys: 2)$" <<<"$out") \
$(grep -cxF "error: $3 is a String Catalog that nothing checks. A module has one catalog," <<<"$out") $(tail -1 <<<"$out")" \
        "1 0/0/0 1 1 error: string catalogs: 1 stand where nothing checks them (above); 0 of 1 failed this check."
}
elsewhere SC71 "a second catalog beside the module's sources (Sources/Tabs/Localizable.xcstrings) fails, named, though the module's own matches" \
    LedgerKit/Sources/Tabs/Localizable.xcstrings
elsewhere SC72 "... a table of another name in Resources (Other.xcstrings) fails the same" LedgerKit/Sources/Tabs/Resources/Other.xcstrings
elsewhere SC73 "... and so does one in a Resources folder deeper in the module (Sources/Tabs/Views/Resources): the build's place is the module's own" \
    LedgerKit/Sources/Tabs/Views/Resources/Localizable.xcstrings
R="$ADV_TMP/only-elsewhere" && mkdir -p "$R/LedgerKit/Sources/Tabs" && cp "$SRC/TabsCopy.swift" "$R/LedgerKit/Sources/Tabs/" &&
    cp "$ADV_TMP/elsewhere-SC71/$CATALOG" "$R/LedgerKit/Sources/Tabs/Localizable.xcstrings" && run
expect "SC74 ... and a repository whose one catalog stands in the wrong place fails on both counts: it is named, and nothing was checked" \
    "$code $(grep -c 'LedgerKit/Sources/Tabs/Localizable.xcstrings is a String Catalog that nothing checks' <<<"$out") \
$(grep -c '^error: no String Catalog at ' <<<"$out")" "1 1 1"

module not-json Tabs TabsCopy && echo '{ "strings" : ' >"$R/$CATALOG" && run
expect "SC27 a catalog that is not JSON fails, saying it cannot be read" \
    "$(found) $(grep -c "^error: $CATALOG (or a .stringsdata of Tabs) cannot be read as a String Catalog:$" <<<"$out")" "1 0/0/0 1"

module newline Tabs TabsCopy && keys 'History' 'Today' && text="$(cat "$R/$CATALOG")" && printf '%s' "$text" >"$R/$CATALOG"
passes "SC28 the final newline is set aside: a catalog that ends without one, as the tool writes it, passes"
keys 'History' 'Today' && echo >>"$R/$CATALOG" && run
expect "SC29 ... but only that one: a blank line at the end fails with the diff" "$(found)" "1 0/0/1"

module elsewhere Tabs TabsCopy && keys 'History' 'Today' && mv "$R/.derivedData" "$ADV_TMP/built-elsewhere" && run
default="$(found)"
run "$ADV_TMP/built-elsewhere" && absolute="$(found)"
run built-elsewhere
expect "SC30 the derived data is .derivedData in the repository unless the second argument names another, absolute or relative to the caller" \
    "$default|$absolute|$(found)" "1 0/0/0|0 0/0/0|0 0/0/0"
out="$(/bin/bash "$SCRIPT" "$R" "$ADV_TMP/built-elsewhere" extra 2>&1)"
expect "SC31 a third argument is a usage error (exit 2)" "$? $(grep -c '^usage: ' <<<"$out")" "2 1"

# ---- moved from CatalogBuildAdversarialTests.auditKey_isFoundationsKey ---------------------------
# Twelve lookups; each passes when the catalog's key is the one shown.
keyed() { # <case> <Source> <the lookup, for the case's name> <key, as JSON text>
    module "keyed-$2" Keyed "$2" && keys "$4"
    passes "$1 (moved from auditKey_isFoundationsKey) $3 is keyed $4"
}
keyed SC32 Key01Copy '"Week \(week) of \(total)" (Int, Int)' 'Week %lld of %lld'
keyed SC33 Key02Copy '"Next: \(name) · \(tag)" (String, String)' 'Next: %@ · %@'
keyed SC34 Key03Copy '"\(week) of \(total) sets · \(name) lb moved" (Int, Int, String)' '%lld of %lld sets · %@ lb moved'
keyed SC35 PercentPlainCopy '"100% done"' '100% done'
keyed SC36 PercentValueCopy '"\(week)% of the block" (Int)' '%lld%% of the block'
keyed SC37 Key06Copy '"Can'"'"'t open \"\(name)\"" (String)' 'Can'"'"'t open \"%@\"'
keyed SC38 Key07Copy '"Rest\tday", a tab,' 'Rest\tday'
keyed SC39 Key08Copy '"Line one\nLine two", a line feed,' 'Line one\nLine two'
keyed SC40 Key09Copy '"Up next \u{2014} \(name)" (String)' "$(printf 'Up next \xe2\x80\x94 %%@')" # an em dash, U+2014
keyed SC41 Key10Copy '#"Back\slash \#(name)"# (String)' 'Back\\slash %@'
keyed SC42 Key11Copy '"\(name)" (String)' '%@'
keyed SC43 Key12Copy '"\(week) × \(total) @ \(name)" (Int, Int, String)' '%lld × %lld @ %@'

# ---- moved from CopyFileAdversarialTests.parameterType_decidesTheSpecifier -----------------------
module type-int Sets SetsIntCopy && keys '%@ sets'
fails_both_ways "SC44 (moved from parameterType_decidesTheSpecifier) \"\\(count) sets\" with an Int against a catalog keyed %@ sets fails both ways" \
    '"%lld sets"' '"%@ sets"'
keys '%lld sets'
passes "SC45 (moved from parameterType_decidesTheSpecifier) ... and passes against %lld sets"
module type-string Sets SetsStringCopy && keys '%lld sets'
fails_both_ways "SC46 (moved from parameterType_decidesTheSpecifier) with a String against %lld sets it fails both ways" \
    '"%@ sets"' '"%lld sets"'
keys '%@ sets'
passes "SC47 (moved from parameterType_decidesTheSpecifier) ... and passes against %@ sets"

# ---- moved from CopyFileAdversarialTests.lookupInAComment_isNotALookup ---------------------------
module in-a-comment Start OnlyAComment && keys 'Start workout' && run
expect "SC48 (moved from lookupInAComment_isNotALookup) a lookup inside a // comment is none: one key reported, the catalog's" \
    "$(found) $(unused '"Start workout"')" "1 0/1/0 1"

# ---- moved from CopyAuditAllowedAdversarialTests.catalogAndCopyFile_disagree_isAFinding ----------
# The code looks up "Start workout"; the catalog's one key is nearly that.
nearly() { # <case> <what differs> <the catalog's key> <that key as the script shows it>
    module "nearly-$1" Start StartCopy && keys "$3"
    fails_both_ways "$1 (moved from catalogAndCopyFile_disagree_isAFinding) a catalog key that differs by $2 fails both ways" \
        '"Start workout"' "$4"
}
nearly SC49 'a capital' 'Start Workout' '"Start Workout"'
nearly SC50 'a trailing space' 'Start workout ' '"Start workout "'
nearly SC51 'a leading space' ' Start workout' '" Start workout"'
nearly SC52 'two spaces' 'Start  workout' '"Start  workout"'
nearly SC53 'a no-break space (U+00A0)' "$(printf 'Start\xc2\xa0workout')" "$(printf '"Start\xc2\xa0workout" (spelled "Start\\u{A0}workout")')"
nearly SC54 'a full stop' 'Start workout.' '"Start workout."'
nearly SC55 'an en dash (U+2013) for the space' "$(printf 'Start\xe2\x80\x93workout')" \
    "$(printf '"Start\xe2\x80\x93workout" (spelled "Start\\u{2013}workout")')"

# ---- moved from CopyAuditAllowedAdversarialTests.oneSideMissing_isAFindingPerKey -----------------
module no-lookup Tabs NoLookup && keys 'History' 'Today' && run
expect "SC56 (moved from oneSideMissing_isAFindingPerKey) a catalog with Today and History and a module with no lookup: two keys reported" \
    "$(found) $(unused '"History"') $(unused '"Today"')" "1 0/2/0 1 1"
module no-key Start StartCopy && keys && run
expect "SC57 (moved from oneSideMissing_isAFindingPerKey) a lookup of \"Start workout\" and a catalog with no keys: one key reported" \
    "$(found) $(lacked '"Start workout"')" "1 1/0/0 1"

# ---- the inputs of CopyFileAdversarialTests.interpolationNotABareParameter_isAFinding ------------
# That test expected a finding from CopyAudit for each of its eleven inputs: the audit derived a key only
# from a bare Int or String parameter. The derivation is gone (F09 S1 fix round 1), and with it that rule:
# the compiler keys any interpolation, and the catalog is checked against the compiler's key. So the
# expectation here is another one, the key the compiler gives each input. All eleven compile. Three do
# so with a warning (SC67), which a build that treats warnings as errors would stop on; a package target's
# build does not (review U2). This step holds a catalog to the compiler's key whatever it is: the key of
# SC60, %lf, is one StringCatalog.problems refuses (a key's values are whole numbers and texts; in
# ModuleCopyTests), as the tester's ST18 says of a counted key's forms.
interpolated() { # <case> <Source> <the lookup, for the case's name> <key, as JSON text>...
    local name="$1 (input of interpolationNotABareParameter_isAFinding) $3 is keyed $4${5:+ and $5}"
    module "interpolated-$2" Keyed "$2"
    shift 3
    keys "$@"
    passes "$name"
}
interpolated SC58 WeekPlusOneCopy '"Week \(week + 1)" (week: Int)' 'Week %lld'
interpolated SC59 StaticTotalCopy '"\(total) weeks" (total: a static property, 8)' '%lld weeks'
interpolated SC60 MovedDoubleCopy '"\(value) lb moved" (value: Double)' '%lf lb moved'
interpolated SC61 SetsInt64Copy '"\(count) sets" (count: Int64)' '%lld sets'
interpolated SC62 SetsSubstringCopy '"\(count) sets" (count: Substring)' '%@ sets'
interpolated SC63 SetsOptionalCopy '"\(count) sets" (count: Int?)' '%@ sets'
interpolated SC64 WeekSomeIntegerCopy '"Week \(week)" (week: some BinaryInteger)' 'Week %@'
interpolated SC65 SetsFormattedCopy '"\(count, format: .number) sets" (count: Int)' '%@ sets'
interpolated SC66 SetsUppercasedCopy '"\(count.uppercased()) sets" (count: String)' '%@ sets'
interpolated SC69 OtherMembersParameterCopy '"\(week) weeks" (week: another member, a function) beside "Week \(week)" (week: Int)' '%@ weeks' 'Week %lld'
interpolated SC70 NestedLookupCopy '"\(String(localized: "Start workout", bundle: .module)) now", a lookup inside the key,' '%@ now' 'Start workout'
check "SC67 ... and the compiler warns of the three whose value it keys %@ as a debug description: Int?, some BinaryInteger and a function" \
    is "$(sed -n "s|.*/\([A-Za-z0-9]*\.swift\):[0-9:]* warning: 'appendInterpolation' is deprecated: Localized string interpolation produces an unlocalized, debug description.*|\1|p" <<<"$compiler_says" | sort -u | tr '\n' ' ')" \
    "OtherMembersParameterCopy.swift SetsOptionalCopy.swift WeekSomeIntegerCopy.swift "

finish
