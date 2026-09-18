# ADR-001: Native Swift + SwiftUI for iPhone and Apple Watch

**Status:** Accepted · **Date:** 2026-09-16

## Context

Ledger is marketed to Apple users. Its core differentiator is a paired Apple
Watch app that owns live workout tracking (sets, weight via Digital Crown,
heart rate, rest timer with haptics) and shares one live workout with the
phone, plus deep Apple Health integration. The design (`design/prototype/`)
targets iOS 26 Liquid Glass conventions and a 46 mm watch face.

## Options considered

| Option | Verdict | Why |
|---|---|---|
| **Swift 6 + SwiftUI, native iOS + watchOS** | **Chosen** | Only option with first-class watchOS, HealthKit workout sessions and mirroring, ActivityKit Live Activities, WidgetKit complications, Liquid Glass fidelity, App Store polish. |
| React Native / Expo | Rejected | No supported watchOS target; HealthKit and workout mirroring require native modules anyway; watch app would be a second codebase. |
| Flutter | Rejected | watchOS not a supported platform; same native-module burden. |
| Kotlin Multiplatform (shared logic) | Rejected | No Android in scope; adds a toolchain for zero user benefit. |
| Native with UIKit | Rejected | SwiftUI is the only reasonable UI layer on watchOS and is the platform default on iOS 26. |

## Decision

- Swift 6.3, Swift 6 language mode, strict concurrency.
- SwiftUI for all UI on both platforms.
- Minimum deployment: iOS 26.0 / watchOS 26.0 (matches the design's Liquid
  Glass assumptions; by launch these will be one major version behind current).
- All product code in one local Swift package (`LedgerKit`) with strict target
  boundaries; app targets are thin.

## Consequences

- Apple-only product. This is aligned with the market intent.
- CI requires macOS runners (cost accepted; see `docs/ci-cd.md`).
- Watch and phone share the entire domain layer (one `WorkoutEngine`), which is
  the main efficiency win of going native-shared rather than two codebases.
- Team must follow Swift 6 concurrency discipline; the standards doc encodes it.
