#!/usr/bin/env bash
# Validates a restored compilation cache before the build, so Xcode's own check skips it (issue #161;
# docs/ci-cd.md, "Compilation cache"). Before compiling, Xcode runs ValidateCAS: llvm-cas --validate-if-needed
# --allow-recovery, which validates in a child process and kills it after a fixed 120 s. The parent reads
# that timeout as invalid data and drops the cache ("recovered from invalid data"), so a slow runner's build
# starts cold. This runs the same check in-process, without that cap. Once it passes, the CAS's
# v1.validation holds this boot's time, and Xcode's check prints "validation skipped".
#
#   scripts/ci-cas-validate.sh [<cas directory>]   (default .derivedData/CompilationCache.noindex/builtin)
#
# Prints the outcome and its time (a ::notice on GitHub Actions, a ::warning when the cache was dropped or
# the check failed). A report, never a gate: it exits 0 whatever happens.
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

# now: the clock in whole seconds, bash's SECONDS; CI_CAS_CLOCK names a command that prints it instead, the
# adversarial suite's seam so a reported time is exact rather than a 1 s tick that may fall mid-run (#178).
now() { if [[ -n "${CI_CAS_CLOCK:-}" ]]; then "$CI_CAS_CLOCK"; else echo "$SECONDS"; fi; }

validate() {
    local cas="${1:-.derivedData/CompilationCache.noindex/builtin}" tool out status started took
    # llvm-cas creates a CAS that is missing, so a missing one is never handed to it.
    if [[ ! -d "$cas" ]]; then say notice "no compilation cache at $cas, nothing to validate"; return; fi
    if ! tool="$(xcrun --find llvm-cas 2>&1)" || [[ ! -x "$tool" ]]; then
        say warning "no llvm-cas in the selected Xcode (${tool%%$'\n'*}); Xcode validates $cas itself"
        return
    fi
    started=$(now)
    out="$("$tool" --cas "$cas" --validate-if-needed --check-hash --allow-recovery --in-process 2>&1)"
    status=$? took=$(($(now) - started))
    out="${out%%$'\n'*}"
    if [[ $status -ne 0 ]]; then
        say warning "llvm-cas could not validate $cas (exit $status, $took s): ${out:-no output}; Xcode validates it itself"
    elif [[ "$out" == *recovered* ]]; then
        say warning "pre-validation: $out, $took s: the restored cache was invalid and is dropped, so this build is cold"
    else
        say notice "pre-validation: ${out:-no output}, $took s"
    fi
}

validate "$@"
exit 0
