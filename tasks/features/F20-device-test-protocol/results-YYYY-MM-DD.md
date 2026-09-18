# F20 device protocol — results YYYY-MM-DD

Copy this file to `results-<date>.md`, fill every row, commit with the run.

| | |
|---|---|
| Date | YYYY-MM-DD |
| Commit | `<sha>` |
| Build | TestFlight build `<n>` / local Debug |
| iPhone | model · iOS `<version (build)>` |
| Apple Watch | model · watchOS `<version (build)>` |
| Tester | |
| Duration | |

## Results

| # | Scenario | Result (pass/fail) | Observed timing | `mirroringDegraded` flipped? | Notes / linked criterion on fail |
|---|---|---|---|---|---|
| 1 | Start from phone | | watch set-ready after … s | | |
| 2 | Start from wrist | | phone Resume after … s · HR after … s | | |
| 3 | Log alternately | | max propagation … ms | | |
| 4 | Phone in bag 10 min | | catch-up after … s | | |
| 5 | Bluetooth off mid-workout | | | | |
| 6 | Kill phone app mid-workout | | | | |
| 7 | Kill watch app mid-workout | | | | |
| 8 | Apple Workout started concurrently | | banner after … s | | |
| 9 | Finish on watch | | | | Health entry: yes/no · HR: yes/no |
| 10 | Finish on phone | | watch summary after … s | | Health entries: count |
| 11 | Discard | | | | |
| 12 | Standalone + pull-back | | History after … s | | HR filled after … |
| 13 | Both finish while partitioned | | | | set count · finishedAt source |
| 14 | Always-On | | | | |

## Diagnostics snapshots
Paste the Diagnostics screen values (both devices) after scenarios 3, 4 and 13.

## Issues filed
- …

## Verdict
M2 exit criterion met: yes / no
