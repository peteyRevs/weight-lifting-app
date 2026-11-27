#!/usr/bin/env bash
# The compilation cache's outcome in one build, for the CI log (issue #153; docs/ci-cd.md, "Compilation
# cache"). Reads the build result bundle check.sh wrote and prints:
#   - Xcode's "N hits / M cacheable tasks (P%)" note (the CompilationCacheMetrics section);
#   - ValidateCAS's outcome and time: "validated successfully", "validation skipped" or "recovered from
#     invalid data" (llvm-cas --validate-if-needed; the last means the restored cache was dropped), and a
#     warning when that recovery came at 115 s or more: llvm-cas's 120 s cap, not corruption (#161);
#   - with a second argument, the cache directory's size, the size of the entry a save would take.
# On GitHub Actions each line is a ::notice annotation, so the run's summary shows it.
#
#   scripts/ci-cache-report.sh <build result bundle> [<cache directory>]
#
# A report, never a gate: it exits 0 whatever it finds or fails to read, saying so as a warning.
set -uo pipefail

say() { # <notice|warning> <message>
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        printf '::%s title=Compilation cache::%s\n' "$1" "$2"
    elif [[ $1 == warning ]]; then
        printf 'compilation cache: warning: %s\n' "$2"
    else
        printf 'compilation cache: %s\n' "$2"
    fi
}

report() {
    local bundle="${1:-}" cas="${2:-}" log lines size
    if [[ -z "$bundle" ]]; then say warning "no build result bundle named"; return; fi
    if [[ ! -d "$bundle" ]]; then say warning "no build result bundle at $bundle (did the build start?)"; return; fi
    if ! log="$(xcrun xcresulttool get log --type build --compact --path "$bundle" 2>&1)"; then
        say warning "xcresulttool could not read the build log in $bundle: ${log%%$'\n'*}"
        return
    fi
    # Each build-log section that ran a command names it in commandDetails and keeps its output.
    if ! lines="$(jq -r '
        [.. | objects | select(.commandInvocationDetails.commandDetails? | type == "string")] as $ran
        | def output: .commandInvocationDetails.emittedOutput // "" | gsub("^\\s+|\\s+$"; "");
        ($ran | map(select(.commandInvocationDetails.commandDetails | startswith("CompilationCacheMetrics")))
            | if length == 0 then "no hit rate in the build log (caching off, or the build stopped before its end)"
              else map(output | ltrimstr("note: ")) | join("; ") end),
        ($ran | map(select(.commandInvocationDetails.commandDetails | startswith("ValidateCAS ")))
            | if length == 0 then "ValidateCAS did not run (no cache restored, or this boot already validated it)"
              else map("ValidateCAS: \(output | if . == "" then "no output" else . end), \(.duration // 0 | floor) s")
                  | join("; ") end),
        ($ran | map(select((.commandInvocationDetails.commandDetails | startswith("ValidateCAS "))
                and (output | test("recovered")) and (.duration // 0) >= 115))
            | .[] | "warning: ValidateCAS recovered after \(.duration | floor) s, at or past the 120 s llvm-cas gives its"
                + " out-of-process check: a timeout, not a corrupt cache, yet the cache was dropped (#161)")' <<<"$log" 2>&1)"; then
        say warning "the build log in $bundle is not the JSON expected: ${lines%%$'\n'*}"
        return
    fi
    while IFS= read -r line; do
        if [[ "$line" == "warning: "* ]]; then say warning "${line#warning: }"; else say notice "$line"; fi
    done <<<"$lines"
    if [[ -n "$cas" ]]; then
        if [[ -d "$cas" ]] && size="$(du -sh "$cas" 2>/dev/null)"; then
            say notice "${size%%[[:space:]]*} in $cas"
        else
            say notice "no cache directory at $cas"
        fi
    fi
}

report "$@"
exit 0
