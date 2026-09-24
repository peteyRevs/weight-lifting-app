#!/usr/bin/env bash
# commit-msg hook (lefthook.yml). Conventional Commits — release-please derives
# the version and changelog from these, so the prefix is not cosmetic.
set -euo pipefail

MESSAGE_FILE="${1:?usage: check-commit-msg.sh <path-to-commit-message>}"
SUBJECT="$(grep -v '^#' "$MESSAGE_FILE" | sed '/^[[:space:]]*$/d' | head -1)"

# Merge, revert and fixup commits are written by git itself.
if [[ "$SUBJECT" =~ ^(Merge|Revert|fixup!|squash!) ]]; then
    exit 0
fi

if [[ ! "$SUBJECT" =~ ^(feat|fix|chore|docs|test|refactor|perf|ci|build)(\([a-z0-9-]+\))?!?:\ .+ ]]; then
    cat >&2 <<'USAGE'
error: commit message is not a Conventional Commit.

  <type>[(scope)][!]: <subject>

  type  = feat | fix | chore | docs | test | refactor | perf | ci | build
  scope = lowercase, digits, dashes (optional)
  !     = breaking change (optional)

  e.g.  feat(domain): add Weight
        fix(watch): keep the session alive across a wrist-down
USAGE
    echo "got: $SUBJECT" >&2
    exit 1
fi
