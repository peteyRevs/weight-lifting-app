#!/usr/bin/env bash
# scripts/check-string-catalogs.sh, attacked by the G2 tester (F09 S1 close-out, 2026-10-05). The implementer's
# suite beside this one (string-catalogs.adv.sh, SC00-SC70) proves the step; these cases (ST..) are the ones it
# does not have, written from docs/engineering-standards.md §7 ("Who checks what", 1; "Catalog") before the
# script was read: comments in both directions, modules beside each other, layouts, a second language, paths
# with spaces, a repository that cannot be written, keys a shell could mangle, and a tool that fails.
# A case named "Reach" or "Limit" pins what the step does not do and says whose it is; it fails when that changes.
# As in the other suite, nothing is hand-made build output: the sources below are compiled by the real compiler,
# and each case runs the real script (under /bin/bash, 3.2 on macOS) on a throwaway repository. No simulator.
# needs macOS: the fixtures are compiled by xcrun swiftc, and the script runs xcrun xcstringstool.
set -uo pipefail
source "$(dirname "$0")/lib.sh"

SCRIPT="${ADV_CHECK_STRING_CATALOGS:-$ROOT/scripts/check-string-catalogs.sh}" # override: mutation-test this suite
SRC="$ADV_TMP/sources"
DATA="$ADV_TMP/stringsdata"
BUILD=".derivedData/Build/Intermediates.noindex/LedgerKit.build" # in a repository; iOS is Debug-iphonesimulator
mkdir -p "$SRC" "$DATA" "$ADV_TMP/objects"

# ---- the fixture sources -------------------------------------------------------------------------
# lookup <file> <string literal>: a source whose one lookup is that literal.
lookup() {
    printf 'import Foundation\nprivate func text() -> String { String(localized: %s, bundle: .module) }\n' "$2" \
        >"$SRC/$1.swift"
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
cat >"$SRC/CommentCopy.swift" <<'SWIFT'
import Foundation
enum CommentCopy {
    static var today: String { String(localized: "Today", bundle: .module, comment: "Tab title") }
    static var history: String { String(localized: "History", bundle: .module) }
}
SWIFT
cat >"$SRC/FirstComment.swift" <<'SWIFT'
import Foundation
enum FirstComment { static var today: String { String(localized: "Today", bundle: .module, comment: "The tab") } }
SWIFT
cat >"$SRC/SecondComment.swift" <<'SWIFT'
import Foundation
enum SecondComment { static var today: String { String(localized: "Today", bundle: .module, comment: "The screen") } }
SWIFT
cat >"$SRC/SetsCopy.swift" <<'SWIFT'
import Foundation
enum SetsCopy {
    static func sets(_ count: Int) -> String { String(localized: "\(count) sets", bundle: .module) }
}
SWIFT
cat >"$SRC/HostileCopy.swift" <<'SWIFT'
import Foundation
enum HostileCopy {
    static var price: String { String(localized: "Costs $5 `now` *really* $(exit 3)", bundle: .module) }
    static var flag: String { String(localized: "-n", bundle: .module) }
    static var option: String { String(localized: "--stringsdata", bundle: .module) }
}
SWIFT
echo 'enum NoLookup {}' >"$SRC/NoLookup.swift"
lookup StartCopy '"Start workout"'
lookup SettingsCopy '"Settings"'
lookup ApostropheCopy '"Can'"'"'t open"'

if ! compiler_says="$(cd "$ADV_TMP/objects" && xcrun swiftc -c -wmo -module-name Fixtures \
    -emit-localized-strings -emit-localized-strings-path "$DATA" "$SRC"/*.swift 2>&1)"; then
    fail "ST00 the fixture sources compile, and the compiler writes their .stringsdata" "$compiler_says"
    finish
    exit 1
fi
check "ST00 the fixture sources compile, and the compiler writes one .stringsdata per source" \
    is "$(find "$DATA" -name '*.stringsdata' | grep -c .)" "$(find "$SRC" -name '*.swift' | grep -c .)"

# ---- fixture repositories (the other suite's helpers, with the same meaning) ---------------------------
# module <repository> <Module> <Source>...: adds a module to the repository $ADV_TMP/<repository>: those
# sources, and their .stringsdata where the iOS build leaves them. Sets $R, $CATALOG and $OBJECTS.
module() {
    local source
    R="$ADV_TMP/$1"
    CATALOG="LedgerKit/Sources/$2/Resources/Localizable.xcstrings"
    OBJECTS="$R/$BUILD/Debug-iphonesimulator/$2-t.build/Objects-normal/arm64"
    mkdir -p "$R/LedgerKit/Sources/$2/Resources" "$OBJECTS"
    shift 2
    for source in "$@"; do
        cp "$SRC/$source.swift" "$R/$(dirname "$(dirname "$CATALOG")")/"
        cp "$DATA/$source.stringsdata" "$OBJECTS/"
    done
}
# unit <language> <text>: one language's text of an entry, as xcstringstool writes it.
unit() {
    printf '        "%s" : {\n          "stringUnit" : {\n            "state" : "translated",\n' "$1"
    printf '            "value" : "%s"\n          }\n        }' "$2"
}
# entry <key> [<comment> [<German text>]]: a catalog entry as xcstringstool writes it, its English text the key.
entry() {
    printf '    "%s" : {\n' "$1"
    [[ -z "${2:-}" ]] || printf '      "comment" : "%s",\n' "$2"
    printf '      "localizations" : {\n'
    [[ -z "${3:-}" ]] || printf '%s,\n' "$(unit de "$3")"
    printf '%s\n      }\n    }' "$(unit en "$1")"
}
# catalog <entry>...: the current module's catalog, those entries in that order, in the tool's layout.
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
    if [[ -n "${ST_SHOW:-}" ]]; then printf '%s\n' "---- exit $code" "$out"; fi
}
# found: "<exit code> <lookups the catalog lacks>/<catalog keys no code looks up>/<diffs against the tool>"
found() {
    printf '%s %s/%s/%s' "$code" "$(grep -c '^  the code looks up ' <<<"$out")" \
        "$(grep -c '^  the catalog has the key ' <<<"$out")" "$(grep -c '^--- LedgerKit/' <<<"$out")"
}
lacked() { grep -cF "  the code looks up $1 (" <<<"$out"; }
unused() { grep -cxF "  the catalog has the key $1, which no code looks up" <<<"$out"; }
matched() { grep -c "^string catalog matches the code: LedgerKit/Sources/$1/Resources/Localizable.xcstrings (keys: [0-9]*)$" <<<"$out"; }
expect() {
    if [[ "$2" == "$3" ]]; then pass "$1"; else
        fail "$1" "got:  $2
want: $3
$out"
    fi
}
passes() { run; expect "$1" "$(found) $(grep -c '^string catalog matches the code: ' <<<"$out")" "0 0/0/0 1"; }
fails_both_ways() { run; expect "$1" "$(found) $(lacked "$2") $(unused "$3")" "1 1/1/0 1 1"; }
fails_on_layout() { run; expect "$1" "$(found)" "1 0/0/1"; }

# ---- a translator's comment: written in code, the catalog's the same sentence (standards §7) ----------
module comment-missing Tabs CommentCopy && keys 'History' 'Today' && run
expect "ST01 a comment the code gives (comment:) and the catalog lacks fails: the diff adds it" \
    "$(found) $(grep -cx -e '+      "comment" : "Tab title",' <<<"$out")" "1 0/0/1 1"
module comment-same Tabs CommentCopy && catalog "$(entry 'History')" "$(entry 'Today' 'Tab title')"
passes "ST02 ... and passes once the catalog has that sentence"
# Standards §7 says "A translator's comment is written in code (comment:), and the catalog's is the same
# sentence". The tool keeps a comment the code does not give, so the step passes one (the other suite's SC15
# builds its sound module with one). Either the step refuses it or §7 says a comment may stand in the catalog
# alone: until that is ruled this pins what happens (test-findings.md, F9-S1-13).
module comment-only-catalog Tabs TabsCopy && catalog "$(entry 'History')" "$(entry 'Today' 'Only the catalog says this')"
passes "ST03 Spec question: a comment only the catalog gives passes, though §7 has a translator's comment written in code"
module comment-twice Tabs FirstComment SecondComment && catalog "$(entry 'Today' 'The tab')" && run
first="$code"
catalog "$(entry 'Today' 'The screen')" && run
second="$code"
catalog "$(entry 'Today' 'The screen\nThe tab')" && run
expect "ST04 one key looked up with two comments: the catalog holds both, in order, on two lines; either one alone fails" \
    "$first $second $(found)" "1 1 0 0/0/0"

# ---- modules beside each other -----------------------------------------------------------------------
module prefix Tabs TabsCopy && keys 'History' 'Settings' 'Today'
module prefix TabsExtra SettingsCopy && keys 'Settings' && run
expect "ST05 a module whose name starts with another's keeps its lookups to itself: Tabs' unused key is still unused" \
    "$(found) $(unused '"Settings"') $(matched TabsExtra)" "1 0/1/0 1 1"
module same-key First TabsCopy && keys 'History' 'Today'
module same-key Second TabsCopy && keys 'History' && run
expect "ST06 the same lookups in two modules, one catalog lacking a key: that module fails, named, and the other passes" \
    "$(found) $(matched First) $(grep -c "^error: LedgerKit/Sources/Second/Resources/Localizable.xcstrings and Second's code disagree on the keys:$" <<<"$out")" \
    "1 1/0/0 1 1"
module no-swift Empty && keys 'Today' && run
expect "ST07 a catalog in a module with no Swift file fails: there is nothing to compare it with" \
    "$(found) $(grep -c 'has nothing to be compared with' <<<"$out")" "1 0/0/0 1"
module beside Tabs TabsCopy && keys 'History' 'Today'
mkdir -p "$R/LedgerKit/Sources/Loose" "$R/$BUILD/Debug-iphonesimulator/Loose-t.build/Objects-normal/arm64" &&
    cp "$SRC/StartCopy.swift" "$R/LedgerKit/Sources/Loose/" &&
    cp "$DATA/StartCopy.stringsdata" "$R/$BUILD/Debug-iphonesimulator/Loose-t.build/Objects-normal/arm64/" && run
expect "ST08 Reach: lookups in a module that has no catalog are not this step's (CopyAudit refuses a copy file there): 1 checked, exit 0" \
    "$(found) $(tail -1 <<<"$out")" "0 0/0/0 string catalogs: 1 checked, each matches its module's code"

# ---- the build output's age ---------------------------------------------------------------------------
module edited Tabs TabsCopy && keys 'History' 'Today' &&
    echo 'enum Later { static var settings: String { String(localized: "Settings", bundle: .module) } }' \
        >>"$R/LedgerKit/Sources/Tabs/TabsCopy.swift" && run
expect "ST09 Limit: a source edited since the build is compared as it was built (check.sh builds first; by hand, build first)" \
    "$(found)" "0 0/0/0"

module intel Tabs TabsCopy && keys 'History' 'Today' &&
    mv "$OBJECTS" "$(dirname "$OBJECTS")/x86_64" && run
expect "ST36 Reach: an x86_64 build's output is not read: the clear failure, not a pass (the step reads Objects-normal/arm64)" \
    "$(found) $(grep -c 'has nothing to be compared with' <<<"$out")" "1 0/0/0 1"
# The compiler writes JSON for every source, one without a lookup too, so an empty .stringsdata is a write cut
# short (a full disk: F00 notes 17 and 19 record a green build with empty output). Here the catalog lacks the
# key that source looks up, and only that file could say so.
module cut-short Tabs TabsCopy SettingsCopy && keys 'History' 'Today' && : >"$OBJECTS/SettingsCopy.stringsdata" && run
expect "ST37 an empty .stringsdata is not read as a source without a lookup: the step fails, it does not pass a catalog that lacks the key" \
    "$([[ $code -ne 0 ]] && echo failed) $(matched Tabs)" "failed 0"

# ---- the layout is the tool's --------------------------------------------------------------------------
module crlf Tabs TabsCopy && keys 'History' 'Today' && perl -pi -e 's/\n/\r\n/' "$R/$CATALOG"
fails_on_layout "ST10 a catalog with CRLF line endings fails with the diff"
module indent Tabs TabsCopy && keys 'History' 'Today' && perl -pi -e 's/^( +)/$1$1/' "$R/$CATALOG"
fails_on_layout "ST11 four-space indent fails with the diff"
module tabs Tabs TabsCopy && keys 'History' 'Today' && perl -pi -e 's/^  /\t/' "$R/$CATALOG"
fails_on_layout "ST12 a tab for the first indent fails with the diff"
module colon Tabs TabsCopy && keys 'History' 'Today' && perl -pi -e 's/" : /": /' "$R/$CATALOG"
fails_on_layout "ST13 \"key\": value, without the space before the colon, fails with the diff"
module bom Tabs TabsCopy && keys 'History' 'Today' && { printf '\xef\xbb\xbf'; cat "$R/$CATALOG"; } >"$R/with-bom" &&
    mv "$R/with-bom" "$R/$CATALOG" && run
expect "ST14 a byte-order mark before the catalog fails" "$code" "1"
module trailing Tabs TabsCopy && keys 'History' 'Today' && perl -pi -e 's/\{$/{ /' "$R/$CATALOG"
fails_on_layout "ST15 a space at the end of a line fails with the diff"

# ---- a second language -----------------------------------------------------------------------------------
module german Tabs TabsCopy && catalog "$(entry 'History' '' 'Verlauf')" "$(entry 'Today')"
passes "ST16 a German text beside the English one does not fail a catalog (standards §7 forbids no second language)"
module german-unused Tabs TabsCopy && catalog "$(entry 'History')" "$(entry 'Settings' '' 'Einstellungen')" "$(entry 'Today')" && run
expect "ST17 ... and a key no code looks up fails though it has a translation" "$(found) $(unused '"Settings"')" "1 0/1/0 1"

# ---- a counted key's forms are the catalog's own rules, which CopyAudit holds ------------------------------
module counted Sets SetsCopy && cat >"$R/$CATALOG" <<'JSON'
{
  "sourceLanguage" : "en",
  "strings" : {
    "%lld sets" : {
      "localizations" : {
        "en" : {
          "variations" : {
            "plural" : {
              "other" : {
                "stringUnit" : {
                  "state" : "translated",
                  "value" : "%lld sets"
                }
              }
            }
          }
        }
      }
    }
  },
  "version" : "1.0"
}
JSON
passes "ST18 Reach: a counted key without its \"one\" form passes this step (StringCatalog.problems refuses it, in ModuleCopyTests)"

# ---- paths with spaces -----------------------------------------------------------------------------------
module 'a repository with spaces' Tabs TabsCopy && keys 'History' 'Today'
passes "ST19 a repository whose path has spaces passes"
keys 'Today' 'History'
fails_on_layout "ST20 ... and fails on its layout as any other"
mv "$R/.derivedData" "$ADV_TMP/derived data with spaces" && keys 'History' 'Today' && run "$ADV_TMP/derived data with spaces"
expect "ST21 ... with its build output in a folder whose path has spaces" "$(found) $(matched Tabs)" "0 0/0/0 1"
mkdir -p "$ADV_TMP/tmp with spaces"
out="$(cd "$ADV_TMP" && TMPDIR="$ADV_TMP/tmp with spaces" /bin/bash "$SCRIPT" "$R" "$ADV_TMP/derived data with spaces" 2>&1)"
code=$?
expect "ST22 ... and with a temporary folder whose path has spaces, which it leaves empty" \
    "$(found) $(find "$ADV_TMP/tmp with spaces" -mindepth 1 | grep -c .)" "0 0/0/0 0"

# ---- a repository that cannot be written -------------------------------------------------------------------
# locked <name> <want from found>: the script on $R with every file and folder of it read-only.
locked() {
    chmod -R a-w "$R"
    run
    chmod -R u+w "$R"
    expect "$1" "$(found)" "$2"
}
module locked-pass Tabs TabsCopy && keys 'History' 'Today'
locked "ST23 a read-only repository: a catalog that matches passes" "0 0/0/0"
module locked-keys Tabs TabsCopy && keys 'History' 'Settings' 'Today'
locked "ST24 ... one with a key no code looks up fails the same" "1 0/1/0"
module locked-layout Tabs TabsCopy && keys 'Today' 'History'
locked "ST25 ... and one with its keys out of order fails the same: the copy the tool writes is writable" "1 0/0/1"
module no-tmp Tabs TabsCopy && keys 'History' 'Today' && mkdir -p "$ADV_TMP/locked-tmp" && chmod a-w "$ADV_TMP/locked-tmp"
out="$(cd "$ADV_TMP" && TMPDIR="$ADV_TMP/locked-tmp" /bin/bash "$SCRIPT" "$R" 2>&1)"
code=$?
chmod u+w "$ADV_TMP/locked-tmp"
expect "ST26 a temporary folder that cannot be written fails the step: no pass without the comparison" \
    "$([[ $code -ne 0 ]] && echo failed) $(grep -c '^string catalogs: ' <<<"$out")" "failed 0"

# ---- keys a shell could mangle -------------------------------------------------------------------------------
module hostile Hostile HostileCopy && keys '--stringsdata' '-n' 'Costs $5 `now` *really* $(exit 3)'
passes "ST27 keys that hold \$, backticks, *, \$(...) and a leading dash are compared as they are written"
keys '--stringsdata' '-n' 'Costs $5 `now` *really* $(exit 4)'
fails_both_ways "ST28 ... and a near miss in such a key is named, both ways, exactly" \
    '"Costs $5 `now` *really* $(exit 3)"' '"Costs $5 `now` *really* $(exit 4)"'

# ---- near misses the other suite does not have (the code looks up "Start workout", or "Can't open") ---------
nearly() { # <case> <Source> <the code's key as shown> <what differs> <the catalog's key> <that key as shown>
    module "nearly-$1" Start "$2" && keys "$5"
    fails_both_ways "$1 a catalog key that differs by $4 fails both ways" "$3" "$6"
}
nearly ST29 ApostropheCopy "\"Can't open\"" 'a typographic apostrophe (U+2019)' "$(printf 'Can\xe2\x80\x99t open')" \
    "$(printf '"Can\xe2\x80\x99t open" (spelled "Can\\u{2019}t open")')"
nearly ST30 StartCopy '"Start workout"' 'a zero-width space (U+200B)' "$(printf 'Start\xe2\x80\x8b workout')" \
    "$(printf '"Start\xe2\x80\x8b workout" (spelled "Start\\u{200B} workout")')"
nearly ST31 StartCopy '"Start workout"' 'a tab for the space' 'Start\tworkout' '"Start\tworkout"'
nearly ST32 StartCopy '"Start workout"' 'a line feed at the end' 'Start workout\n' '"Start workout\n"'
nearly ST33 StartCopy '"Start workout"' 'a fullwidth capital (U+FF33)' "$(printf '\xef\xbc\xb3tart workout')" \
    "$(printf '"\xef\xbc\xb3tart workout" (spelled "\\u{FF33}tart workout")')"

# ---- the tool fails ------------------------------------------------------------------------
# with_tool <body of a fake xcstringstool>: the script on $R with an xcrun whose xcstringstool is that.
with_tool() {
    mkdir -p "$ADV_TMP/fake-bin"
    printf '#!/bin/sh\nif [ "$1" = xcstringstool ]; then\n%s\nfi\nexec /usr/bin/xcrun "$@"\n' "$1" >"$ADV_TMP/fake-bin/xcrun"
    chmod +x "$ADV_TMP/fake-bin/xcrun"
    out="$(cd "$ADV_TMP" && PATH="$ADV_TMP/fake-bin:$PATH" /bin/bash "$SCRIPT" "$R" 2>&1)"
    code=$?
}
module tool-fails Tabs TabsCopy && keys 'History' 'Today' && with_tool 'echo "xcstringstool: no such tool" >&2; exit 72'
expect "ST34 when xcstringstool fails, the step fails and shows what the tool said: a catalog is not passed unread" \
    "$code $(grep -c 'xcrun xcstringstool sync failed on a copy of' <<<"$out") $(grep -c 'no such tool' <<<"$out") $(matched Tabs)" "1 1 1 0"
# A tool that exits 0 and writes nothing would pass any layout. That is not pinned here: the tool is Xcode's,
# pinned by .xcode-version, and the other suite's SC10, SC11, SC16 and SC29 fail the day it stops writing.

finish
