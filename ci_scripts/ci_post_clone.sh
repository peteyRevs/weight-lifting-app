#!/bin/sh
# Xcode Cloud runs this after cloning, from inside ci_scripts/ (docs/ci-cd.md §5).
# The build number is Xcode Cloud's: the later assignment in Base.xcconfig wins.
set -eu
: "${CI_BUILD_NUMBER:?Xcode Cloud sets CI_BUILD_NUMBER}"
printf '\nCURRENT_PROJECT_VERSION = %s\n' "$CI_BUILD_NUMBER" >> "${CI_PRIMARY_REPOSITORY_PATH:?}/Config/Base.xcconfig"
echo "CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER}"
