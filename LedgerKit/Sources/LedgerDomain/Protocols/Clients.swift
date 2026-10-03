import Foundation

// The device clients a store reaches through `@Dependency` (architecture §13; F07). Shape only, like
// `HealthStore`: the brief that first needs one adds its methods, and its live implementation.
// `Sendable`, so a nonisolated dependency key can hold one and a `@MainActor` store can call it.

/// Haptic feedback: the engine's `.haptic` effects, played by the workout stores (F10, F18).
public protocol HapticsClient: Sendable {}

/// Local notifications: the rest-over alert while the phone app is in the background (F10 schedules it, F23
/// implements it).
public protocol NotificationsClient: Sendable {}

/// The Live Activity for elapsed and rest time on the Lock Screen and Dynamic Island (F21).
public protocol LiveActivitiesClient: Sendable {}
