#!/usr/bin/env bash
# The F01 adversarial suites (scripts/tests/adversarial/), run by check.sh step 2
# with the other script tests. Host-only: no network, no simulator.
exec "$(dirname "$0")/adversarial/run.sh"
