#!/bin/sh
# Xcode Cloud runs this after cloning, from inside ci_scripts/ (docs/ci-cd.md §5).
# The build number is Xcode Cloud's: the later assignment in Base.xcconfig wins.
set -eu
case "${CI_BUILD_NUMBER:-}" in
    '' | *[!0-9]*) echo "error: CI_BUILD_NUMBER must be a whole number, got '${CI_BUILD_NUMBER:-}'" >&2; exit 1 ;;
esac
printf '\nCURRENT_PROJECT_VERSION = %s\n' "$CI_BUILD_NUMBER" >> "${CI_PRIMARY_REPOSITORY_PATH:?}/Config/Base.xcconfig"
echo "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}"
