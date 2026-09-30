#!/usr/bin/env bash
# F03 criterion 7, against main: a change to the seeded exercise catalog must raise ExerciseCatalog.version
# above main's, because F05 re-seeds only when the version rises. The history in catalog.version.sha is
# append-only: every line main has must still be there, unchanged and in order (a PR adds its own line
# and may rewrite that one until it merges). ExerciseCatalogTests then check the last line against the file.
#
# The base is the merge base of HEAD with origin/main, or with main when there is no origin/main (a local
# clone without a remote). The working tree is compared, so uncommitted edits count. CI checks out full
# history (pr.yml, fetch-depth: 0), so origin/main is there.
#
#   scripts/check-catalog-version.sh   # used by check.sh step 2
#
# Exit 0: the catalog is unchanged, or changed with a higher version. 1: it changed and the version did
# not rise, the version fell, or a line main has in catalog.version.sha changed. 2: no base, or a version
# that cannot be read.
set -euo pipefail

cd "$(dirname "$0")/.."
JSON="LedgerKit/Sources/LedgerDomain/Resources/exercises.json"
HISTORY="LedgerKit/Sources/LedgerDomain/Resources/catalog.version.sha"
SOURCE="LedgerKit/Sources/LedgerDomain/Catalog/ExerciseCatalog.swift"

base_ref=""
for ref in origin/main main; do
    if git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then base_ref="$ref" && break; fi
done
if [[ -z "$base_ref" ]]; then
    echo "error: no origin/main or main to compare the exercise catalog against. Fetch main (a CI checkout" >&2
    echo "       needs fetch-depth: 0) and run again." >&2
    exit 2
fi
if ! base="$(git merge-base HEAD "$base_ref")"; then
    echo "error: HEAD shares no history with $base_ref, so the catalog has no base to compare against." >&2
    exit 2
fi

# The `public static let version = N` line of ExerciseCatalog.swift, read from stdin.
version_in() { sed -nE 's/^[[:space:]]*public static let version = ([0-9]+)[[:space:]]*$/\1/p'; }
current="$(version_in <"$SOURCE")"
if [[ -z "$current" ]]; then
    echo "error: no 'public static let version = N' line in $SOURCE" >&2
    exit 2
fi
if base_source="$(git show "$base:$SOURCE" 2>/dev/null)"; then
    previous="$(version_in <<<"$base_source")"
    if [[ -z "$previous" ]]; then
        echo "error: no 'public static let version = N' line in $SOURCE at $base_ref ($base)" >&2
        exit 2
    fi
else
    previous=0 # main predates ExerciseCatalog: any version is a rise
fi

short="${base:0:7}"
if (( current < previous )); then
    echo "error: ExerciseCatalog.version fell from $previous ($base_ref, $short) to $current." >&2
    exit 1
fi
changed=false
if [[ "$(git rev-parse --verify --quiet "$base:$JSON" || true)" != "$(git hash-object "$JSON")" ]]; then changed=true; fi
if [[ $changed == true ]] && (( current <= previous )); then
    cat >&2 <<MSG
error: $JSON differs from $base_ref ($short), but ExerciseCatalog.version is still $current.
       Raise it to $((previous + 1)) or more in $SOURCE, and end $(basename "$HISTORY") with that version
       and the file's SHA-256 (shasum -a 256 exercises.json): F05 re-seeds only when the version rises.
MSG
    exit 1
fi

# The lines main already has, without comments and blanks, must open the current history unchanged.
entries() { grep -v -e '^#' -e '^[[:space:]]*$' || true; }
if merged="$(git show "$base:$HISTORY" 2>/dev/null)"; then
    merged="$(entries <<<"$merged")"
    if [[ ! -f "$HISTORY" ]]; then
        echo "error: $HISTORY is gone, but $base_ref has it. Append to it; never delete it." >&2
        exit 1
    fi
    now="$(entries <"$HISTORY")"
    if [[ -n "$merged" && "$now" != "$merged" && "$now" != "$merged"$'\n'* ]]; then
        diff -u --label "$HISTORY at $base_ref" --label "$HISTORY" <(printf '%s\n' "$merged") \
            <(printf '%s\n' "$now") >&2 || true
        echo "error: $(basename "$HISTORY") changed a line $base_ref has (above). Append; never edit a merged line." >&2
        exit 1
    fi
fi
if [[ $changed == true ]]; then
    echo "exercise catalog changed since $base_ref ($short): version $previous -> $current"
else
    echo "exercise catalog unchanged since $base_ref ($short): version $current"
fi
