import Foundation

/// Live phone ⇄ watch envelope transport (architecture §8, ADR-005). Shape only: full contract in F17.
public protocol LiveWorkoutTransport: Sendable {}

/// Non-live phone ⇄ watch transfer: programs, settings, finished workouts (architecture §8).
/// Shape only: full contract in F19.
public protocol CompanionTransport: Sendable {}
