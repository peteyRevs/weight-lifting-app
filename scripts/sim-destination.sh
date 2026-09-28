#!/usr/bin/env bash
# Prints an xcodebuild destination by UDID for one given by name and OS (an id= passes as is), and
# unpairs that simulator (F01 notes, "First CI run"). By name, xcodebuild also matches every iPhone
# paired with a watch of that name, whatever its OS; the macos-26 runner pairs same-named watches on
# two runtimes, so the watch by name was ambiguous (exit 70). By UDID it is not; unpairing is defence
# in depth.
set -euo pipefail

destination="$1" platform="" name="" os="" udid=""
IFS=, read -ra fields <<<"$1"
for field in "${fields[@]}"; do
    case "$field" in
        id=*) udid="${field#*=}" ;; platform=*) platform="${field#*=}" ;;
        name=*) name="${field#*=}" ;; OS=*) os="${field#*=}" ;;
    esac
done
if [[ -z "$udid" ]]; then
    udid="$(xcrun simctl list devices available --json | jq -r --arg name "$name" \
        --arg runtime "com.apple.CoreSimulator.SimRuntime.${platform% Simulator}-${os//./-}" \
        'first(.devices[$runtime][]? | select(.name == $name) | .udid) // empty')"
    [[ -n "$udid" ]] || { echo "error: no available simulator matches '$1' (name and OS, or id)" >&2; exit 1; }
    destination="platform=$platform,id=$udid"
fi
pairs="$(xcrun simctl list pairs --json |
    jq -r --arg udid "$udid" '.pairs | to_entries[] | select(.value.watch.udid == $udid or .value.phone.udid == $udid) | .key')"
for pair in $pairs; do echo "sim-destination: unpairing $udid" >&2; xcrun simctl unpair "$pair" >&2; done
echo "$destination"
