#!/usr/bin/env bash
# Fails unless every module's String Catalog agrees with the module's code (F09): the catalog's keys are
# exactly the keys the code looks up, and the file is written as Xcode's own tool writes it.
#
# The keys come from the compiler, not from reading Swift: every Xcode build of the iOS scheme writes the
# keys it extracted from each source file to <Source>.stringsdata, beside the object files. For every
# LedgerKit/Sources/<Module>/Resources/Localizable.xcstrings this script
#   1. fails every lookup that is not in a copy file (<Name>Copy.swift, <Name>Copy+<Area>.swift), with its
#      file and line, whether or not the catalog has its key: a bare Text("...") in a view or a preview is
#      one, and so is Button("\(a)/\(b)"), which has no letter for the source audit to see;
#   2. compares the catalog's keys with the keys the copy files look up, byte for byte, and names each key
#      the code looks up that the catalog lacks and each catalog key no code looks up;
#   3. when 1 and 2 find nothing, runs `xcrun xcstringstool sync` (what Xcode runs to update a catalog) on a copy
#      in a temporary folder, and shows a diff when the tool would write the file differently: a comment
#      that differs from the code's, keys out of order, a key written twice, another layout.
# The final newline is set aside: the tool ends the file without one, a hand-written catalog with one.
#
# Only the .stringsdata of the Swift files the module has today are read. An incremental build keeps the
# file of a source that was since deleted or renamed, and its keys would look used. The generated ones
# (GeneratedStringSymbols_Localizable, resource_bundle_accessor, ExtractedAppShortcutsMetadata) are left
# out: they come from the catalog and the package, not from a lookup an author wrote.
#
# A module has one catalog, at that path. Any other .xcstrings under LedgerKit/Sources fails this step: the
# build would compile it into the module's bundle, and nothing would check it.
#
# Only the iOS build is read. A module that only the watch build compiles (LedgerWatchAppKit,
# WatchFeatureWorkout) gets its catalog with F18, when this step learns to read the watch build
# (docs/engineering-standards.md §7); until then a catalog there fails with "nothing to be compared with".
#
# The committed catalog is only read, and may be read-only. Nothing here builds: run it after an iOS build
# (check.sh step 3). A known limit: a source edited since that build is compared by the .stringsdata the
# build wrote, so a run by hand needs a build first; check.sh always builds before this step.
#
#   scripts/check-string-catalogs.sh [<repository root> [<derived data>]]
#
# <repository root> defaults to this script's repository, <derived data> to .derivedData in that root
# (check.sh's -derivedDataPath).
#
# Exit 0: every catalog matches. 1: a catalog does not match or has no build output to compare with (the
# others are still checked), a catalog stands somewhere else, or there is no catalog at all: the app has
# copy, so finding none means the catalogs moved, and this step must not pass on nothing. 2: wrong arguments.
set -euo pipefail

if [[ $# -gt 2 ]]; then
    echo "usage: $0 [<repository root> [<derived data>]]" >&2
    exit 2
fi
ROOT="${1:-$(dirname "$0")/..}"
DERIVED="${2:-$ROOT/.derivedData}"
[[ "$DERIVED" == /* ]] || DERIVED="$PWD/$DERIVED" # relative to the caller, not to the root entered below
if ! cd "$ROOT"; then
    echo "error: no repository root at $ROOT" >&2
    exit 2
fi

# Where the iOS build (scheme Ledger, Debug, an arm64 simulator) leaves the package's intermediates; a
# module's files are in <Module>-t.build/Objects-normal/arm64 there. The watch build's are not read.
INTERMEDIATES="$DERIVED/Build/Intermediates.noindex/LedgerKit.build/Debug-iphonesimulator"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/ledger-string-catalogs.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# xcstringstool leaves a catalog untouched, whatever its layout, when no key or comment changes. To make
# it write, the copy is synced twice: first with one more key, which no catalog has, then without it.
# The tool drops that key again, and the file it leaves is the catalog as it writes it.
EXTRA_KEY="check-string-catalogs.sh: a key no catalog has, so that xcstringstool writes the file"
cat >"$WORK/extra.stringsdata" <<JSON
{
  "source": "scripts/check-string-catalogs.sh",
  "tables": {
    "Localizable": [
      { "comment": "", "key": "$EXTRA_KEY", "location": { "startingColumn": 1, "startingLine": 1 } }
    ]
  },
  "version": 1
}
JSON

# One line per finding, tagged and a tab before it; nothing when the module is sound. "O": a lookup outside
# the copy files. "K": a key that only one side has, the code's side being the copy files' lookups. A key
# is shown as JSON text, and again with each non-ASCII character as a Swift escape when it has one: two
# keys can look the same. A copy file is named as CopyAudit.isCopyFile names one.
# shellcheck disable=SC2016 # a jq program, not shell
KEY_FINDINGS='
def hex: def digit: "0123456789ABCDEF"[.:. + 1]; if . < 16 then digit else (. / 16 | floor | hex) + (. % 16 | digit) end;
def shown:
    tojson as $text
    | if any(explode[]; . > 126)
      then $text + " (spelled " + ($text | explode | map(if . > 126 then "\\u{" + hex + "}" else [.] | implode end) | join("")) + ")"
      else $text end;
[inputs
    | (input_filename | sub(".*/"; "") | sub("\\.stringsdata$"; ".swift")) as $file
    | .tables.Localizable[]?
    | {key, at: "\($file):\(.location.startingLine // "?")", copy: ($file | test("^\\w+Copy(\\+\\w+)?\\.swift$"))}] as $all
| ($all | map(select(.copy))) as $lookups
| ($lookups | map(.key) | unique) as $used
| ($all | map(.key) | unique) as $anywhere
| ($catalog[0].strings | keys_unsorted) as $catalogued
| (($all | map(select(.copy | not)) | unique_by([.at, .key]))[] | "O\t  \(.at) looks up \(.key | shown)"),
  (($used - $catalogued)[] as $key
    | "K\t  the code looks up \($key | shown) (\([$lookups[] | select(.key == $key) | .at] | unique | join(", "))), which is not a key of the catalog"),
  (($catalogued - $anywhere)[] | "K\t  the catalog has the key \(shown), which no code looks up")
'

# with_final_newline <file> <copy>: the file, ending in a newline whether or not it did. The copy is a new
# file, written with cat: cp would give it the mode of a read-only catalog, and the newline could not be added.
with_final_newline() {
    cat "$1" >"$2"
    if [[ -n "$(tail -c 1 "$1")" ]]; then printf '\n' >>"$2"; fi
}

TAB="$(printf '\t')"

# check_catalog <catalog>: 0 when it matches its module's code; otherwise says why on stderr and returns 1.
check_catalog() {
    local catalog="$1" module objects work source data findings outside keys copy tool_says
    local files=() flags=() unbuilt=()
    module="$(basename "$(dirname "$(dirname "$catalog")")")"
    objects="$INTERMEDIATES/$module-t.build/Objects-normal/arm64"
    work="$WORK/$module"
    mkdir -p "$work"

    while IFS= read -r -d '' source; do
        data="$objects/$(basename "$source" .swift).stringsdata"
        if [[ -f "$data" ]]; then
            files+=("$data")
            flags+=(--stringsdata "$data")
        else
            unbuilt+=("$source")
        fi
    done < <(find "LedgerKit/Sources/$module" -type f -name '*.swift' -print0 | LC_ALL=C sort -z)

    if [[ ${#files[@]} -eq 0 ]]; then
        cat >&2 <<MSG
error: $catalog has nothing to be compared with: the iOS build left no
       .stringsdata for $module's Swift files in
       $objects
       One of three things. iOS has not been built: scripts/check.sh builds it, then runs this step.
       Or $module is a watch module, which the iOS build does not compile: this step reads the iOS
       build only, and LedgerWatchAppKit and WatchFeatureWorkout get their catalogs with F18
       (docs/engineering-standards.md §7), so take this catalog out until then. Or Xcode's build folder
       is laid out differently now, and this script must follow it.
MSG
        return 1
    fi
    if [[ ${#unbuilt[@]} -gt 0 ]]; then
        echo "error: $catalog cannot be compared with all of $module's code: the iOS build left" >&2
        echo "       no .stringsdata for these files. Build iOS again (scripts/check.sh does), then run this step:" >&2
        printf '         %s\n' "${unbuilt[@]}" >&2
        return 1
    fi

    # Byte for byte, by jq: xcstringstool takes a composed and a decomposed spelling for one key.
    if ! findings="$(jq -rn --slurpfile catalog "$catalog" "$KEY_FINDINGS" "${files[@]}" 2>&1)"; then
        echo "error: $catalog (or a .stringsdata of $module) cannot be read as a String Catalog:" >&2
        printf '%s\n' "$findings" | sed 's/^/       /' >&2
        return 1
    fi
    outside="$(sed -n "s/^O$TAB//p" <<<"$findings")"
    keys="$(sed -n "s/^K$TAB//p" <<<"$findings")"
    if [[ -n "$outside" ]]; then
        cat >&2 <<MSG
error: $module looks up copy outside its copy files:
$outside
       Every lookup of a module is in <Name>Copy.swift or <Name>Copy+<Area>.swift (standards §7), and
       these files are neither. Do not give the catalog a key for such a lookup, and delete one it holds
       only for it. Move the lookup into the copy file and hand the view a String. In Debug-only code
       that needs no translation (a preview, a Debug page), write Text(verbatim: "..."). A literal
       handed to a view is a lookup, with letters or without: Text("..."), Button("\(done)/\(total)").
MSG
    fi
    if [[ -n "$keys" ]]; then
        cat >&2 <<MSG
error: $catalog and $module's code disagree on the keys:
$keys
       Give the catalog a key for each lookup it lacks, spelled exactly as shown, with its English text
       and a comment. Delete a key no code looks up, or look it up in the module's copy file. A key is
       the text in the code, with each value written as its specifier (%lld for an Int, %@ for a String;
       a value of any other type is formatted first and passed as a String) and, only in a text that
       has a value, each % doubled.
MSG
    fi
    [[ -z "$findings" ]] || return 1

    copy="$work/Localizable.xcstrings" # this name: the tool reads the table's name from the file's
    cp "$catalog" "$copy"
    if ! tool_says="$(xcrun xcstringstool sync "$copy" "${flags[@]}" --stringsdata "$WORK/extra.stringsdata" 2>&1 &&
        xcrun xcstringstool sync "$copy" "${flags[@]}" 2>&1)"; then
        echo "error: xcrun xcstringstool sync failed on a copy of $catalog:" >&2
        printf '%s\n' "$tool_says" | sed 's/^/       /' >&2
        return 1
    fi
    with_final_newline "$catalog" "$work/committed"
    with_final_newline "$copy" "$work/synced"
    if ! cmp -s "$work/committed" "$work/synced"; then
        echo "error: $catalog has the keys the code looks up, but is not written as" >&2
        echo "       Xcode's tool writes it (xcrun xcstringstool sync). Lines marked - are the catalog's, + the tool's:" >&2
        diff -u --label "$catalog" --label "$catalog, as xcstringstool writes it" \
            "$work/committed" "$work/synced" >&2 || true
        cat >&2 <<MSG
       Edit the catalog until it reads as the + lines do. The tool keeps the keys in code-unit order,
       writes each key once, indents by two spaces with " : " after a name, and takes a key's comment
       from the code when the lookup gives one (comment:).
MSG
        return 1
    fi
    echo "string catalog matches the code: $catalog (keys: $(jq '.strings | length' "$catalog"))"
}

checked=0 failed=0
for catalog in LedgerKit/Sources/*/Resources/Localizable.xcstrings; do
    [[ -f "$catalog" ]] || continue # no match leaves the pattern itself
    checked=$((checked + 1))
    check_catalog "$catalog" || failed=$((failed + 1))
done

# A catalog anywhere else under the sources is one the loop above did not see.
elsewhere=0
while IFS= read -r -d '' other; do
    if [[ ! "$other" =~ ^LedgerKit/Sources/[^/]+/Resources/Localizable\.xcstrings$ ]]; then
        elsewhere=$((elsewhere + 1))
        echo "error: $other is a String Catalog that nothing checks. A module has one catalog," >&2
        echo "       LedgerKit/Sources/<Module>/Resources/Localizable.xcstrings: move its keys there, or delete it." >&2
    fi
done < <(find LedgerKit/Sources -name '*.xcstrings' -print0 2>/dev/null | LC_ALL=C sort -z)

if [[ $checked -eq 0 ]]; then
    echo "error: no String Catalog at LedgerKit/Sources/<Module>/Resources/Localizable.xcstrings under $PWD." >&2
    echo "       The app has user-facing copy, so the catalogs moved or the root is wrong: nothing was checked." >&2
    exit 1
fi
if [[ $elsewhere -gt 0 ]]; then
    echo "error: string catalogs: $elsewhere stand where nothing checks them (above); $failed of $checked failed this check." >&2
    exit 1
fi
if [[ $failed -gt 0 ]]; then
    echo "error: string catalogs: $failed of $checked failed this check (above)." >&2
    exit 1
fi
echo "string catalogs: $checked checked, each matches its module's code"
